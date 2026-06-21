-- Fix: payment_intents table uses `amount_cents` (integer) rather than `amount`.
-- The RPCs must compute the payable amount from cents to avoid:
--   record "intent" has no field "amount"

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
  intent public.payment_intents%rowtype;
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

  if intent.id is null then
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
    set status = 'expired', updated_at = now()
    where id = intent.id;
    return json_build_object('success', false, 'error', 'Payment intent expired');
  end if;

  amount_to_pay := coalesce(intent.amount_cents, 0)::numeric / 100;
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

  -- Validate category eligibility against merchant categories.
  if not exists (
    select 1
    from unnest(merchant_categories) as c
    where lower(regexp_replace(trim(c), '[^a-zA-Z0-9]', '', 'g')) = normalized_key
  ) then
    return json_build_object('success', false, 'error', 'Coupon not eligible for this merchant');
  end if;

  -- Compute available category balance for the user from the transactions ledger.
  select
    coalesce(sum(
      case
        when t.receiver_profile_id = uid then t.amount
        when t.sender_profile_id = uid and t.type = 'userToMerchant' then -t.amount
        else 0
      end
    ), 0)
  into available
  from public.transactions t
  where t.status = 'completed'
    and coalesce(lower(regexp_replace(trim(t.metadata->>'category'), '[^a-zA-Z0-9]', '', 'g')), '') = normalized_key
    and (t.receiver_profile_id = uid or t.sender_profile_id = uid);

  if available < amount_to_pay then
    return json_build_object('success', false, 'error', 'Insufficient category balance');
  end if;

  -- Get merchant wallet.
  select id, currency_code
  into merchant_wallet
  from public.wallets
  where merchant_id = intent.merchant_id
    and currency_code = intent.currency_code
  limit 1;

  if merchant_wallet is null then
    return json_build_object('success', false, 'error', 'Merchant wallet not found');
  end if;

  new_transaction_id := uuid_generate_v4();
  txn_ref := 'TXN-' || replace(new_transaction_id::text, '-', '');

  insert into public.transactions (
    id,
    transaction_reference,
    sender_profile_id,
    receiver_merchant_id,
    receiver_wallet_id,
    amount,
    currency_code,
    note,
    type,
    status,
    metadata,
    created_at,
    updated_at,
    completed_at
  ) values (
    new_transaction_id,
    txn_ref,
    uid,
    intent.merchant_id,
    merchant_wallet.id,
    amount_to_pay,
    intent.currency_code,
    'QR payment',
    'userToMerchant',
    'completed',
    jsonb_build_object('category', normalized_key, 'payment_intent_id', intent.id),
    now(),
    now(),
    now()
  );

  -- Mark intent completed.
  update public.payment_intents
  set
    status = 'completed',
    transaction_id = new_transaction_id,
    transaction_reference = txn_ref,
    completed_at = now(),
    updated_at = now(),
    paid_by_profile_id = uid
  where id = intent.id;

  return json_build_object(
    'success', true,
    'transaction_id', new_transaction_id,
    'transaction_reference', txn_ref
  );
exception
  when others then
    return json_build_object(
      'success', false,
      'error', 'Payment failed',
      'code', sqlstate,
      'detail', sqlerrm
    );
end;
$$;

grant execute on function public.pay_payment_intent_with_category(uuid, text) to authenticated;

create or replace function public.pay_payment_intent_with_coupon(
  p_payment_intent_id uuid,
  p_coupon_id uuid
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid;
  intent public.payment_intents%rowtype;
  merchant_row record;
  merchant_wallet record;
  coupon_row record;
  new_transaction_id uuid;
  txn_ref text;
  amount_to_pay numeric;
  merchant_categories text[];
begin
  uid := auth.uid();
  if uid is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;
  if p_payment_intent_id is null then
    return json_build_object('success', false, 'error', 'Payment intent missing');
  end if;
  if p_coupon_id is null then
    return json_build_object('success', false, 'error', 'Coupon missing');
  end if;

  -- Lock intent to prevent double confirmation.
  select *
  into intent
  from public.payment_intents
  where id = p_payment_intent_id
  for update;

  if intent.id is null then
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
    set status = 'expired', updated_at = now()
    where id = intent.id;
    return json_build_object('success', false, 'error', 'Payment intent expired');
  end if;

  amount_to_pay := coalesce(intent.amount_cents, 0)::numeric / 100;
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

  -- Lock coupon.
  select *
  into coupon_row
  from public.coupons
  where id = p_coupon_id and profile_id = uid
  for update;

  if coupon_row is null then
    return json_build_object('success', false, 'error', 'Coupon not found');
  end if;
  if lower(coalesce(coupon_row.status, '')) <> 'active' then
    return json_build_object('success', false, 'error', 'Coupon is not active');
  end if;

  if lower(coalesce(coupon_row.currency_code, '')) <> lower(coalesce(intent.currency_code, '')) then
    return json_build_object('success', false, 'error', 'Coupon currency does not match');
  end if;

  if not (coupon_row.category = any(merchant_categories)) then
    return json_build_object('success', false, 'error', 'Coupon not eligible for this merchant');
  end if;

  if coupon_row.balance < amount_to_pay then
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
      'coupon_id', coupon_row.id,
      'coupon_category', coupon_row.category
    )
  ) returning id into new_transaction_id;

  -- Credit merchant wallet.
  update public.wallets
  set balance = balance + amount_to_pay
  where id = merchant_wallet.id;

  insert into public.wallet_entries (wallet_id, transaction_id, entry_type, amount, balance_before, balance_after)
  values (merchant_wallet.id, new_transaction_id, 'credit', amount_to_pay, merchant_wallet.balance, merchant_wallet.balance + amount_to_pay);

  -- Deduct coupon balance.
  update public.coupons
  set balance = balance - amount_to_pay
  where id = coupon_row.id;

  -- Mark intent completed.
  update public.payment_intents
  set status = 'completed',
      completed_at = now(),
      paid_by_profile_id = uid,
      transaction_id = new_transaction_id,
      transaction_reference = txn_ref,
      coupon_id = coupon_row.id,
      updated_at = now()
  where id = intent.id;

  return json_build_object(
    'success', true,
    'transaction_id', new_transaction_id,
    'transaction_reference', txn_ref,
    'coupon_new_balance', coupon_row.balance - amount_to_pay,
    'paid_amount', amount_to_pay
  );
exception
  when others then
    return json_build_object('success', false, 'error', 'Payment failed');
end;
$$;

grant execute on function public.pay_payment_intent_with_coupon(uuid, uuid) to authenticated;

commit;
