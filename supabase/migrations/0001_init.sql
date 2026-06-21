-- CaddyMoney: initial Supabase schema (enums, tables, triggers, RLS, RPC)
-- This migration is designed for Supabase Postgres.

begin;

-- Extensions
create extension if not exists "uuid-ossp";
create extension if not exists pgcrypto;

-- ============================================================================
-- Enums
-- ============================================================================
do $$
begin
  if not exists (select 1 from pg_type where typname = 'app_role') then
    create type public.app_role as enum ('standardUser', 'merchant', 'admin');
  end if;

  if not exists (select 1 from pg_type where typname = 'account_status') then
    create type public.account_status as enum ('active', 'inactive', 'suspended', 'deleted');
  end if;

  if not exists (select 1 from pg_type where typname = 'merchant_status') then
    create type public.merchant_status as enum ('pending', 'approved', 'rejected', 'suspended');
  end if;

  if not exists (select 1 from pg_type where typname = 'wallet_owner_type') then
    create type public.wallet_owner_type as enum ('user', 'merchant');
  end if;

  if not exists (select 1 from pg_type where typname = 'transaction_type') then
    create type public.transaction_type as enum ('userToUser', 'userToMerchant', 'refund', 'adjustment');
  end if;

  if not exists (select 1 from pg_type where typname = 'transaction_status') then
    create type public.transaction_status as enum ('pending', 'completed', 'failed', 'cancelled');
  end if;

  if not exists (select 1 from pg_type where typname = 'ledger_entry_type') then
    create type public.ledger_entry_type as enum ('debit', 'credit');
  end if;
end $$;

-- ============================================================================
-- Utilities
-- ============================================================================

create or replace function public.update_updated_at_column()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ============================================================================
-- Core tables
-- ============================================================================

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null unique,
  phone text,
  role public.app_role not null default 'standardUser',
  status public.account_status not null default 'active',
  preferred_language text default 'fr',
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_profiles_email on public.profiles(email);
create index if not exists idx_profiles_role on public.profiles(role);

create trigger update_profiles_updated_at
  before update on public.profiles
  for each row
  execute function public.update_updated_at_column();

create table if not exists public.merchants (
  id uuid primary key default uuid_generate_v4(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  unique_merchant_id text not null unique,
  business_name text not null,
  owner_name text not null,
  business_email text not null,
  business_phone text,
  address_line1 text,
  address_line2 text,
  city text,
  postal_code text,
  country_code text,
  business_category text,
  registration_number text,
  tax_number text,
  status public.merchant_status not null default 'pending',
  approved_by uuid references public.profiles(id),
  approved_at timestamptz,
  rejected_reason text,
  suspended_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Merchant ID generation (defined after merchants table exists)
create or replace function public.generate_unique_merchant_id()
returns text
language plpgsql
as $$
declare
  new_id text;
  done boolean;
begin
  done := false;
  while not done loop
    new_id := 'MCH-' || lpad(floor(random() * 1000000)::text, 6, '0');
    if not exists (select 1 from public.merchants where unique_merchant_id = new_id) then
      done := true;
    end if;
  end loop;
  return new_id;
end;
$$;

create or replace function public.set_merchant_id()
returns trigger
language plpgsql
as $$
begin
  if new.unique_merchant_id is null or new.unique_merchant_id = '' then
    new.unique_merchant_id := public.generate_unique_merchant_id();
  end if;
  return new;
end;
$$;

create trigger before_insert_merchant
  before insert on public.merchants
  for each row
  execute function public.set_merchant_id();

create trigger update_merchants_updated_at
  before update on public.merchants
  for each row
  execute function public.update_updated_at_column();

create index if not exists idx_merchants_profile_id on public.merchants(profile_id);
create index if not exists idx_merchants_status on public.merchants(status);
create index if not exists idx_merchants_unique_id on public.merchants(unique_merchant_id);

create table if not exists public.wallets (
  id uuid primary key default uuid_generate_v4(),
  owner_type public.wallet_owner_type not null,
  profile_id uuid references public.profiles(id) on delete cascade,
  merchant_id uuid references public.merchants(id) on delete cascade,
  currency_code text not null default 'EUR',
  balance numeric(15, 2) not null default 0.00 check (balance >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint wallet_owner_check check (
    (owner_type = 'user' and profile_id is not null and merchant_id is null) or
    (owner_type = 'merchant' and merchant_id is not null and profile_id is null)
  )
);

create trigger update_wallets_updated_at
  before update on public.wallets
  for each row
  execute function public.update_updated_at_column();

create index if not exists idx_wallets_profile_id on public.wallets(profile_id);
create index if not exists idx_wallets_merchant_id on public.wallets(merchant_id);
create index if not exists idx_wallets_owner_type on public.wallets(owner_type);

create table if not exists public.transactions (
  id uuid primary key default uuid_generate_v4(),
  transaction_reference text not null unique,
  sender_profile_id uuid references public.profiles(id),
  sender_wallet_id uuid references public.wallets(id),
  receiver_profile_id uuid references public.profiles(id),
  receiver_merchant_id uuid references public.merchants(id),
  receiver_wallet_id uuid references public.wallets(id),
  amount numeric(15, 2) not null check (amount > 0),
  currency_code text not null default 'EUR',
  note text,
  type public.transaction_type not null,
  status public.transaction_status not null default 'pending',
  failure_reason text,
  metadata jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

-- Transaction reference generation (defined after transactions table exists)
create or replace function public.generate_transaction_reference()
returns text
language plpgsql
as $$
declare
  new_ref text;
  done boolean;
begin
  done := false;
  while not done loop
    new_ref := 'TXN-' || to_char(now(), 'YYYYMMDD') || '-' || lpad(floor(random() * 100000)::text, 5, '0');
    if not exists (select 1 from public.transactions where transaction_reference = new_ref) then
      done := true;
    end if;
  end loop;
  return new_ref;
end;
$$;

create trigger update_transactions_updated_at
  before update on public.transactions
  for each row
  execute function public.update_updated_at_column();

create index if not exists idx_transactions_sender on public.transactions(sender_profile_id);
create index if not exists idx_transactions_receiver on public.transactions(receiver_profile_id);
create index if not exists idx_transactions_merchant on public.transactions(receiver_merchant_id);
create index if not exists idx_transactions_status on public.transactions(status);
create index if not exists idx_transactions_type on public.transactions(type);
create index if not exists idx_transactions_reference on public.transactions(transaction_reference);

create table if not exists public.wallet_entries (
  id uuid primary key default uuid_generate_v4(),
  wallet_id uuid not null references public.wallets(id) on delete cascade,
  transaction_id uuid references public.transactions(id),
  entry_type public.ledger_entry_type not null,
  amount numeric(15, 2) not null check (amount > 0),
  balance_before numeric(15, 2) not null,
  balance_after numeric(15, 2) not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_wallet_entries_wallet_id on public.wallet_entries(wallet_id);
create index if not exists idx_wallet_entries_transaction_id on public.wallet_entries(transaction_id);

create table if not exists public.merchant_status_history (
  id uuid primary key default uuid_generate_v4(),
  merchant_id uuid not null references public.merchants(id) on delete cascade,
  old_status public.merchant_status not null,
  new_status public.merchant_status not null,
  changed_by uuid not null references public.profiles(id),
  reason text,
  created_at timestamptz not null default now()
);

create index if not exists idx_merchant_status_history_merchant on public.merchant_status_history(merchant_id);

-- ============================================================================
-- Triggers: profile/wallet auto-provisioning
-- ============================================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into public.profiles (id, full_name, email, role, phone, preferred_language)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    new.email,
    coalesce((new.raw_user_meta_data->>'role')::public.app_role, 'standardUser'),
    coalesce(new.raw_user_meta_data->>'phone', null),
    coalesce(new.raw_user_meta_data->>'preferred_language', 'fr')
  )
  on conflict (id) do nothing;
  return new;
exception
  when others then
    -- Never block auth signups if profile creation fails.
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_user();

create or replace function public.handle_new_profile()
returns trigger
language plpgsql
as $$
begin
  if new.role in ('standardUser', 'merchant') then
    insert into public.wallets (owner_type, profile_id, currency_code)
    values ('user', new.id, 'EUR')
    on conflict do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists on_profile_created on public.profiles;
create trigger on_profile_created
  after insert on public.profiles
  for each row
  execute function public.handle_new_profile();

create or replace function public.handle_new_merchant()
returns trigger
language plpgsql
as $$
begin
  insert into public.wallets (owner_type, merchant_id, currency_code)
  values ('merchant', new.id, 'EUR')
  on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists on_merchant_created on public.merchants;
create trigger on_merchant_created
  after insert on public.merchants
  for each row
  execute function public.handle_new_merchant();

-- ============================================================================
-- RLS
-- ============================================================================

alter table public.profiles enable row level security;
alter table public.merchants enable row level security;
alter table public.wallets enable row level security;
alter table public.transactions enable row level security;
alter table public.wallet_entries enable row level security;
alter table public.merchant_status_history enable row level security;

-- Recommended: lock down default privileges.
revoke all on table public.profiles from anon, authenticated;
revoke all on table public.merchants from anon, authenticated;
revoke all on table public.wallets from anon, authenticated;
revoke all on table public.transactions from anon, authenticated;
revoke all on table public.wallet_entries from anon, authenticated;
revoke all on table public.merchant_status_history from anon, authenticated;

-- Helpers
create or replace function public.current_user_role()
returns public.app_role
language sql
stable
security definer
set search_path = public
as $$
  select p.role
  from public.profiles p
  where p.id = auth.uid();
$$;

create or replace function public.is_admin(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.profiles p
    where p.id = uid
      and p.role = 'admin'
      and p.status = 'active'
  );
$$;

-- Profiles policies
drop policy if exists "Users can view their own profile" on public.profiles;
create policy "Users can view their own profile"
  on public.profiles
  for select
  to authenticated
  using (auth.uid() = id);

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
  on public.profiles
  for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "Admins can view all profiles" on public.profiles;
create policy "Admins can view all profiles"
  on public.profiles
  for select
  to authenticated
  using (public.is_admin(auth.uid()));

-- Merchants policies
drop policy if exists "Merchants can view their own merchant profile" on public.merchants;
create policy "Merchants can view their own merchant profile"
  on public.merchants
  for select
  to authenticated
  using (auth.uid() = profile_id);

drop policy if exists "Merchants can update their own merchant profile" on public.merchants;
create policy "Merchants can update their own merchant profile"
  on public.merchants
  for update
  to authenticated
  using (auth.uid() = profile_id)
  with check (auth.uid() = profile_id);

drop policy if exists "Users can create merchant applications" on public.merchants;
create policy "Users can create merchant applications"
  on public.merchants
  for insert
  to authenticated
  with check (
    auth.uid() = profile_id and
    public.current_user_role() in ('standardUser', 'merchant')
  );

drop policy if exists "Admins can manage merchants" on public.merchants;
create policy "Admins can manage merchants"
  on public.merchants
  for all
  to authenticated
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

-- Wallets policies (read-only from client; mutations should go through RPC)
drop policy if exists "Owners can view wallets" on public.wallets;
create policy "Owners can view wallets"
  on public.wallets
  for select
  to authenticated
  using (
    auth.uid() = profile_id or
    auth.uid() in (select m.profile_id from public.merchants m where m.id = merchant_id) or
    public.is_admin(auth.uid())
  );

-- Transactions policies (read-only from client; mutations should go through RPC)
drop policy if exists "Owners can view transactions" on public.transactions;
create policy "Owners can view transactions"
  on public.transactions
  for select
  to authenticated
  using (
    auth.uid() = sender_profile_id or
    auth.uid() = receiver_profile_id or
    auth.uid() in (select m.profile_id from public.merchants m where m.id = receiver_merchant_id) or
    public.is_admin(auth.uid())
  );

-- Wallet entries policies (read-only from client)
drop policy if exists "Owners can view wallet entries" on public.wallet_entries;
create policy "Owners can view wallet entries"
  on public.wallet_entries
  for select
  to authenticated
  using (
    wallet_id in (
      select w.id
      from public.wallets w
      where w.profile_id = auth.uid()
         or w.merchant_id in (select m.id from public.merchants m where m.profile_id = auth.uid())
    )
    or public.is_admin(auth.uid())
  );

-- Merchant status history policies
drop policy if exists "Admins can view merchant status history" on public.merchant_status_history;
create policy "Admins can view merchant status history"
  on public.merchant_status_history
  for select
  to authenticated
  using (public.is_admin(auth.uid()));

-- Minimal grants (RLS still applies)
grant select, update on public.profiles to authenticated;
grant select, insert, update on public.merchants to authenticated;
grant select on public.wallets to authenticated;
grant select on public.transactions to authenticated;
grant select on public.wallet_entries to authenticated;
grant select on public.merchant_status_history to authenticated;

-- ============================================================================
-- RPC: atomic money transfers (security definer)
-- ============================================================================

create or replace function public.transfer_user_to_user(
  receiver_user_id uuid,
  transfer_amount numeric,
  transfer_note text default null
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

  transaction_ref := public.generate_transaction_reference();

  insert into public.transactions (
    transaction_reference, sender_profile_id, sender_wallet_id,
    receiver_profile_id, receiver_wallet_id,
    amount, currency_code, note,
    type, status, completed_at
  ) values (
    transaction_ref, sender_id, sender_wallet.id,
    receiver_user_id, receiver_wallet.id,
    transfer_amount, sender_wallet.currency_code, transfer_note,
    'userToUser', 'completed', now()
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
  transfer_note text default null
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

  transaction_ref := public.generate_transaction_reference();

  insert into public.transactions (
    transaction_reference, sender_profile_id, sender_wallet_id,
    receiver_merchant_id, receiver_wallet_id,
    amount, currency_code, note,
    type, status, completed_at
  ) values (
    transaction_ref, sender_id, sender_wallet.id,
    merchant_row.id, merchant_wallet.id,
    transfer_amount, sender_wallet.currency_code, transfer_note,
    'userToMerchant', 'completed', now()
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

grant execute on function public.transfer_user_to_user(uuid, numeric, text) to authenticated;
grant execute on function public.transfer_user_to_merchant(text, numeric, text) to authenticated;

commit;
