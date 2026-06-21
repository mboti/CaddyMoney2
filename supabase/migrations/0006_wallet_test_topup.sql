-- Dev/testing helper: one-time wallet top-up for the authenticated user.
-- Creates a ledger-backed adjustment transaction so it appears in history.

begin;

alter table public.wallets
  add column if not exists test_topup_claimed boolean not null default false;

create or replace function public.claim_test_topup(
  topup_amount numeric default 1000
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid;
  w record;
  new_transaction_id uuid;
  transaction_ref text;
begin
  uid := auth.uid();
  if uid is null then
    return json_build_object('success', false, 'error', 'Not authenticated');
  end if;
  if topup_amount is null or topup_amount <= 0 then
    return json_build_object('success', false, 'error', 'Invalid amount');
  end if;

  select *
  into w
  from public.wallets
  where owner_type = 'user' and profile_id = uid and is_active = true
  for update;

  if w is null then
    return json_build_object('success', false, 'error', 'Wallet not found');
  end if;
  if w.test_topup_claimed then
    return json_build_object('success', false, 'error', 'Top up already claimed');
  end if;

  transaction_ref := public.generate_transaction_reference();

  insert into public.transactions (
    transaction_reference,
    receiver_profile_id,
    receiver_wallet_id,
    amount,
    currency_code,
    note,
    type,
    status,
    completed_at,
    metadata
  ) values (
    transaction_ref,
    uid,
    w.id,
    topup_amount,
    w.currency_code,
    'Test top up',
    'adjustment',
    'completed',
    now(),
    jsonb_build_object('source', 'dev_tool')
  ) returning id into new_transaction_id;

  update public.wallets
  set balance = balance + topup_amount,
      test_topup_claimed = true
  where id = w.id;

  insert into public.wallet_entries (wallet_id, transaction_id, entry_type, amount, balance_before, balance_after)
  values (w.id, new_transaction_id, 'credit', topup_amount, w.balance, w.balance + topup_amount);

  return json_build_object(
    'success', true,
    'transaction_id', new_transaction_id,
    'transaction_reference', transaction_ref,
    'new_balance', w.balance + topup_amount
  );
exception
  when others then
    return json_build_object('success', false, 'error', 'Top up failed');
end;
$$;

grant execute on function public.claim_test_topup(numeric) to authenticated;

commit;
