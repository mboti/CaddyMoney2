-- Extend transfer RPCs to attach payment method metadata to transactions.
-- This keeps the client read-only (RLS) while still allowing rich transaction history.

begin;

create or replace function public.transfer_user_to_user(
  receiver_user_id uuid,
  transfer_amount numeric,
  transfer_note text default null,
  payment_method_id uuid default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  sender_id uuid;
  sender_wallet record;
  receiver_wallet record;
  new_transaction_id uuid;
  transaction_ref text;
  pm record;
  txn_metadata jsonb;
begin
  sender_id := auth.uid();
  if sender_id is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;
  if transfer_amount is null or transfer_amount <= 0 then
    return json_build_object('success', false, 'error', 'Invalid amount');
  end if;
  if receiver_user_id is null then
    return json_build_object('success', false, 'error', 'Receiver missing');
  end if;
  if receiver_user_id = sender_id then
    return json_build_object('success', false, 'error', 'Cannot transfer to self');
  end if;

  select *
  into sender_wallet
  from public.wallets
  where profile_id = sender_id and owner_type = 'user' and is_active = true
  for update;

  if sender_wallet is null then
    return json_build_object('success', false, 'error', 'Sender wallet not found');
  end if;
  if sender_wallet.balance < transfer_amount then
    return json_build_object('success', false, 'error', 'Insufficient balance');
  end if;

  select *
  into receiver_wallet
  from public.wallets
  where profile_id = receiver_user_id and owner_type = 'user' and is_active = true
  for update;

  if receiver_wallet is null then
    return json_build_object('success', false, 'error', 'Receiver wallet not found');
  end if;

  -- Attach payment method snapshot (if provided & owned by sender).
  txn_metadata := '{}'::jsonb;
  if payment_method_id is not null then
    select id, type, brand, last4, exp_month, exp_year
    into pm
    from public.payment_methods
    where id = payment_method_id and user_id = sender_id;

    if pm is null then
      return json_build_object('success', false, 'error', 'Invalid payment method');
    end if;

    txn_metadata := jsonb_build_object(
      'payment_method', jsonb_build_object(
        'id', pm.id,
        'type', pm.type,
        'brand', pm.brand,
        'last4', pm.last4,
        'exp_month', pm.exp_month,
        'exp_year', pm.exp_year
      )
    );
  end if;

  transaction_ref := public.generate_transaction_reference();

  insert into public.transactions (
    transaction_reference, sender_profile_id, sender_wallet_id,
    receiver_profile_id, receiver_wallet_id,
    amount, currency_code, note,
    type, status, completed_at, metadata
  ) values (
    transaction_ref, sender_id, sender_wallet.id,
    receiver_user_id, receiver_wallet.id,
    transfer_amount, sender_wallet.currency_code, transfer_note,
    'userToUser', 'completed', now(), txn_metadata
  ) returning id into new_transaction_id;

  update public.wallets
  set balance = balance - transfer_amount
  where id = sender_wallet.id;

  insert into public.wallet_entries (wallet_id, transaction_id, entry_type, amount, balance_before, balance_after)
  values (sender_wallet.id, new_transaction_id, 'debit', transfer_amount, sender_wallet.balance, sender_wallet.balance - transfer_amount);

  update public.wallets
  set balance = balance + transfer_amount
  where id = receiver_wallet.id;

  insert into public.wallet_entries (wallet_id, transaction_id, entry_type, amount, balance_before, balance_after)
  values (receiver_wallet.id, new_transaction_id, 'credit', transfer_amount, receiver_wallet.balance, receiver_wallet.balance + transfer_amount);

  return json_build_object('success', true, 'transaction_id', new_transaction_id, 'transaction_reference', transaction_ref);
exception
  when others then
    return json_build_object('success', false, 'error', 'Transfer failed');
end;
$$;

create or replace function public.transfer_user_to_merchant(
  merchant_unique_id text,
  transfer_amount numeric,
  transfer_note text default null,
  payment_method_id uuid default null
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  sender_id uuid;
  sender_wallet record;
  merchant_row record;
  merchant_wallet record;
  new_transaction_id uuid;
  transaction_ref text;
  pm record;
  txn_metadata jsonb;
begin
  sender_id := auth.uid();
  if sender_id is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;
  if transfer_amount is null or transfer_amount <= 0 then
    return json_build_object('success', false, 'error', 'Invalid amount');
  end if;
  if merchant_unique_id is null or merchant_unique_id = '' then
    return json_build_object('success', false, 'error', 'Merchant missing');
  end if;

  select *
  into merchant_row
  from public.merchants
  where unique_merchant_id = merchant_unique_id and status = 'approved';

  if merchant_row is null then
    return json_build_object('success', false, 'error', 'Merchant not found or not approved');
  end if;

  select *
  into sender_wallet
  from public.wallets
  where profile_id = sender_id and owner_type = 'user' and is_active = true
  for update;

  if sender_wallet is null then
    return json_build_object('success', false, 'error', 'Sender wallet not found');
  end if;
  if sender_wallet.balance < transfer_amount then
    return json_build_object('success', false, 'error', 'Insufficient balance');
  end if;

  select *
  into merchant_wallet
  from public.wallets
  where merchant_id = merchant_row.id and owner_type = 'merchant' and is_active = true
  for update;

  if merchant_wallet is null then
    return json_build_object('success', false, 'error', 'Merchant wallet not found');
  end if;

  txn_metadata := '{}'::jsonb;
  if payment_method_id is not null then
    select id, type, brand, last4, exp_month, exp_year
    into pm
    from public.payment_methods
    where id = payment_method_id and user_id = sender_id;

    if pm is null then
      return json_build_object('success', false, 'error', 'Invalid payment method');
    end if;

    txn_metadata := jsonb_build_object(
      'payment_method', jsonb_build_object(
        'id', pm.id,
        'type', pm.type,
        'brand', pm.brand,
        'last4', pm.last4,
        'exp_month', pm.exp_month,
        'exp_year', pm.exp_year
      )
    );
  end if;

  transaction_ref := public.generate_transaction_reference();

  insert into public.transactions (
    transaction_reference, sender_profile_id, sender_wallet_id,
    receiver_merchant_id, receiver_wallet_id,
    amount, currency_code, note,
    type, status, completed_at, metadata
  ) values (
    transaction_ref, sender_id, sender_wallet.id,
    merchant_row.id, merchant_wallet.id,
    transfer_amount, sender_wallet.currency_code, transfer_note,
    'userToMerchant', 'completed', now(), txn_metadata
  ) returning id into new_transaction_id;

  update public.wallets
  set balance = balance - transfer_amount
  where id = sender_wallet.id;

  insert into public.wallet_entries (wallet_id, transaction_id, entry_type, amount, balance_before, balance_after)
  values (sender_wallet.id, new_transaction_id, 'debit', transfer_amount, sender_wallet.balance, sender_wallet.balance - transfer_amount);

  update public.wallets
  set balance = balance + transfer_amount
  where id = merchant_wallet.id;

  insert into public.wallet_entries (wallet_id, transaction_id, entry_type, amount, balance_before, balance_after)
  values (merchant_wallet.id, new_transaction_id, 'credit', transfer_amount, merchant_wallet.balance, merchant_wallet.balance + transfer_amount);

  return json_build_object('success', true, 'transaction_id', new_transaction_id, 'transaction_reference', transaction_ref);
exception
  when others then
    return json_build_object('success', false, 'error', 'Transfer failed');
end;
$$;

-- Re-grant execute with updated signatures.
grant execute on function public.transfer_user_to_user(uuid, numeric, text, uuid) to authenticated;
grant execute on function public.transfer_user_to_merchant(text, numeric, text, uuid) to authenticated;

commit;
