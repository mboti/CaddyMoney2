-- Saved payment methods (cards).
-- IMPORTANT: Never store raw PAN/CVC in this table.

begin;

create table if not exists public.payment_methods (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null default 'card',
  brand text not null default 'visa',
  last4 text not null check (char_length(last4) = 4),
  exp_month int not null check (exp_month between 1 and 12),
  exp_year int not null check (exp_year between 2020 and 2100),
  holder_name text,
  nickname text,
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_payment_methods_user on public.payment_methods(user_id, created_at desc);

-- Only one default payment method per user.
create unique index if not exists uq_payment_methods_one_default_per_user
  on public.payment_methods(user_id)
  where is_default;

drop trigger if exists update_payment_methods_updated_at on public.payment_methods;
create trigger update_payment_methods_updated_at
  before update on public.payment_methods
  for each row
  execute function public.update_updated_at_column();

alter table public.payment_methods enable row level security;

drop policy if exists "payment_methods_select_own" on public.payment_methods;
create policy "payment_methods_select_own"
  on public.payment_methods
  for select
  using (user_id = auth.uid());

drop policy if exists "payment_methods_insert_own" on public.payment_methods;
create policy "payment_methods_insert_own"
  on public.payment_methods
  for insert
  with check (user_id = auth.uid());

drop policy if exists "payment_methods_update_own" on public.payment_methods;
create policy "payment_methods_update_own"
  on public.payment_methods
  for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "payment_methods_delete_own" on public.payment_methods;
create policy "payment_methods_delete_own"
  on public.payment_methods
  for delete
  using (user_id = auth.uid());

commit;
