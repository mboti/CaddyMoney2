-- Add category-ledger-backed payment confirmation for QR payment intents.
--
-- Some deployments track "available amounts by service" using transactions.metadata.category
-- rather than the public.coupons table.
--
-- This migration introduces an atomic SECURITY DEFINER function that:
-- - Locks the payment intent to prevent double confirmations
-- - Validates merchant approval + intent expiry
-- - Validates the payer's available category balance by scanning completed transactions
-- - Creates the merchant payment transaction and credits the merchant wallet
-- - Marks the intent completed

begin;

create or replace function public.pay_payment_intent_with_category(
  p_payment_intent_id uuid,
  p_category_key text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid;
  intent record;
  merchant_row record;
  merchant_wallet record;
  new_transaction_id uuid;
  txn_ref text;
  amount_to_pay numeric;
  merchant_categories text[];
  available numeric;
  normalized_key text;
begin
  uid := auth.uid();
  if uid is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;

  if p_payment_intent_id is null then
    return json_build_object('success', false, 'error', 'Payment intent missing');
  end if;

  normalized_key := regexp_replace(coalesce(p_category_key, ''), '[^a-zA-Z0-9]', '', 'g');
  normalized_key := lower(trim(normalized_key));
  if normalized_key = '' then
    return json_build_object('success', false, 'error', 'Category missing');
  end if;

  -- Lock intent to prevent double confirmation.
  select *
  into intent
  from public.payment_intents
  where id = p_payment_intent_id
  for update;

  if intent is null then
    return json_build_object('success', false, 'error', 'Payment intent not found');
  end if;

  if intent.status = 'completed' then
    return json_build_object(
      'success', true,
      'already_paid', true,
      'transaction_id', intent.transaction_id,
      'transaction_reference', intent.transaction_reference
    );
  end if;

  if intent.status <> 'pending' then
    return json_build_object('success', false, 'error', 'Payment intent is not payable');
  end if;

  if intent.expires_at is not null and now() > intent.expires_at then
    update public.payment_intents
    set status = 'expired'
    where id = intent.id;
    return json_build_object('success', false, 'error', 'Payment intent expired');
  end if;

  amount_to_pay := intent.amount;
  if amount_to_pay is null or amount_to_pay <= 0 then
    return json_build_object('success', false, 'error', 'Invalid payment amount');
  end if;

  select id, status, categories
  into merchant_row
  from public.merchants
  where id = intent.merchant_id;

  if merchant_row is null then
    return json_build_object('success', false, 'error', 'Merchant not found');
  end if;
  if merchant_row.status <> 'approved' then
    return json_build_object('success', false, 'error', 'Merchant not approved');
  end if;

  merchant_categories := coalesce(merchant_row.categories, '{}'::text[]);

  -- Validate category eligibility against merchant categories. We compare using a normalized
  -- alphanumeric lowercase key to be resilient to casing/spaces.
  if not exists (
    select 1
    from unnest(merchant_categories) as c
    where lower(regexp_replace(trim(c), '[^a-zA-Z0-9]', '', 'g')) = normalized_key
  ) then
    return json_build_object('success', false, 'error', 'Coupon not eligible for this merchant');
  end if;

  -- Compute available category balance for the user from the transactions ledger.
  -- Credits: completed transactions where user is receiver and metadata.category matches.
  -- Debits: completed user->merchant transactions where user is sender and metadata.category matches.
  select
    coalesce(sum(
      case
        when t.receiver_profile_id = uid
          then t.amount
        when t.sender_profile_id = uid and t.type = 'userToMerchant'
          then -t.amount
        else 0
      end
    ), 0)
  into available
  from public.transactions t
  where t.status = 'completed'
    and t.currency_code = intent.currency_code
    and (t.sender_profile_id = uid or t.receiver_profile_id = uid)
    and lower(regexp_replace(trim(coalesce(t.metadata->>'category','')), '[^a-zA-Z0-9]', '', 'g')) = normalized_key;

  if available < amount_to_pay then
    return json_build_object('success', false, 'error', 'Insufficient coupon balance');
  end if;

  -- Lock merchant wallet.
  select *
  into merchant_wallet
  from public.wallets
  where owner_type = 'merchant' and merchant_id = intent.merchant_id and is_active = true
  for update;

  if merchant_wallet is null then
    return json_build_object('success', false, 'error', 'Merchant wallet not found');
  end if;

  txn_ref := public.generate_transaction_reference();

  insert into public.transactions (
    transaction_reference,
    sender_profile_id,
    receiver_merchant_id,
    receiver_wallet_id,
    amount,
    currency_code,
    note,
    type,
    status,
    completed_at,
    metadata
  ) values (
    txn_ref,
    uid,
    intent.merchant_id,
    merchant_wallet.id,
    amount_to_pay,
    intent.currency_code,
    'QR payment',
    'userToMerchant',
    'completed',
    now(),
    jsonb_build_object(
      'source', 'payment_intent',
      'payment_intent_id', intent.id,
      'category_key', normalized_key
    )
  ) returning id into new_transaction_id;

  -- Credit merchant wallet.
  update public.wallets
  set balance = balance + amount_to_pay
  where id = merchant_wallet.id;

  insert into public.wallet_entries (wallet_id, transaction_id, entry_type, amount, balance_before, balance_after)
  values (merchant_wallet.id, new_transaction_id, 'credit', amount_to_pay, merchant_wallet.balance, merchant_wallet.balance + amount_to_pay);

  -- Mark intent completed.
  update public.payment_intents
  set status = 'completed',
      completed_at = now(),
      paid_by_profile_id = uid,
      transaction_id = new_transaction_id,
      transaction_reference = txn_ref,
      coupon_id = null
  where id = intent.id;

  return json_build_object(
    'success', true,
    'transaction_id', new_transaction_id,
    'transaction_reference', txn_ref,
    'paid_amount', amount_to_pay
  );
exception
  when others then
    return json_build_object('success', false, 'error', 'Payment failed');
end;
$$;

grant execute on function public.pay_payment_intent_with_category(uuid, text) to authenticated;

commit;
