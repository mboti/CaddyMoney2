-- Make UUID generation resilient across Supabase projects.
--
-- Problem:
-- - Some DBs don’t have the `uuid-ossp` extension enabled, causing
--   `uuid_generate_v4()` to fail (and payments to fail).
--
-- Fix:
-- - Prefer `pgcrypto`'s `gen_random_uuid()` (commonly available) when possible.
-- - Provide a `public.uuid_v4()` helper that works with either extension.
-- - Update table defaults + payment RPC code paths to use `public.uuid_v4()`.

begin;

-- Ensure pgcrypto is available for gen_random_uuid().
create extension if not exists "pgcrypto";

create or replace function public.uuid_v4()
returns uuid
language plpgsql
as $$
begin
  begin
    return gen_random_uuid();
  exception
    when undefined_function then
      null;
  end;

  begin
    return uuid_generate_v4();
  exception
    when undefined_function then
      null;
  end;

  raise exception 'UUID generation not available. Enable extension pgcrypto or uuid-ossp.';
end;
$$;

-- Switch commonly-used UUID defaults to the resilient helper.
alter table if exists public.merchants alter column id set default public.uuid_v4();
alter table if exists public.wallets alter column id set default public.uuid_v4();
alter table if exists public.transactions alter column id set default public.uuid_v4();
alter table if exists public.wallet_entries alter column id set default public.uuid_v4();
alter table if exists public.merchant_status_history alter column id set default public.uuid_v4();

alter table if exists public.payment_methods alter column id set default public.uuid_v4();
alter table if exists public.coupons alter column id set default public.uuid_v4();
alter table if exists public.payment_intents alter column id set default public.uuid_v4();

-- Patch payment RPCs to avoid direct uuid_generate_v4() usage.
-- (In case the DB had uuid-ossp disabled but pgcrypto enabled.)

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

  new_transaction_id := public.uuid_v4();
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

commit;
