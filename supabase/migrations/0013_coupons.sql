-- Coupons: category-bound balances that can be used to pay compatible merchants.
--
-- This is intentionally simple for MVP:
-- - One coupon belongs to exactly one category.
-- - One coupon has a remaining balance.
-- - Payments are applied via a SECURITY DEFINER RPC (atomic + backend validation).

begin;

create table if not exists public.coupons (
  id uuid primary key default uuid_generate_v4(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  category text not null,
  currency_code text not null default 'EUR',
  balance numeric(15, 2) not null default 0.00 check (balance >= 0),
  status text not null default 'active' check (status in ('active', 'paused', 'expired')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_coupons_profile on public.coupons(profile_id);
create index if not exists idx_coupons_category on public.coupons(category);

drop trigger if exists update_coupons_updated_at on public.coupons;
create trigger update_coupons_updated_at
  before update on public.coupons
  for each row
  execute function public.update_updated_at_column();

alter table public.coupons enable row level security;

drop policy if exists "coupons_select_own" on public.coupons;
create policy "coupons_select_own"
  on public.coupons
  for select
  to authenticated
  using (profile_id = auth.uid());

-- Disallow client writes (coupon issuance/changes should be done by admin/backend).
drop policy if exists "coupons_no_insert" on public.coupons;
create policy "coupons_no_insert"
  on public.coupons
  for insert
  to authenticated
  with check (false);

drop policy if exists "coupons_no_update" on public.coupons;
create policy "coupons_no_update"
  on public.coupons
  for update
  to authenticated
  using (false)
  with check (false);

drop policy if exists "coupons_no_delete" on public.coupons;
create policy "coupons_no_delete"
  on public.coupons
  for delete
  to authenticated
  using (false);

commit;
