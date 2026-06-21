-- Payment Intents: server-created payment requests (used for merchant QR flow).
-- A Payment Intent represents a short-lived request that can later be paid by a customer.
--
-- SECURITY MODEL
-- - Merchants (authenticated users with an associated merchants row) can create/select
--   only their own intents.
-- - The client should never be trusted to finalize or validate payments; use RPC/Edge
--   Functions with additional server-side checks.

begin;

-- Optional: status constraint (kept as text on purpose to remain flexible with app).
-- You can expand the allowed values later without breaking clients.

create table if not exists public.payment_intents (
  id uuid primary key default uuid_generate_v4(),

  -- Merchant that will receive the funds.
  merchant_id uuid not null references public.merchants(id) on delete cascade,

  -- Opaque token intended for QR encoding.
  -- Customers scan the token; backend resolves token -> intent and enforces rules.
  token text not null unique,

  currency_code text not null default 'EUR',

  -- Store in major units to match current Flutter model.
  -- (If you later move to cents, add amount_cents and keep amount for backward compat.)
  amount numeric(15, 2) not null check (amount > 0),

  status text not null default 'pending' check (status in ('pending', 'completed', 'expired', 'cancelled')),

  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_payment_intents_merchant_created
  on public.payment_intents(merchant_id, created_at desc);

create index if not exists idx_payment_intents_token
  on public.payment_intents(token);

drop trigger if exists update_payment_intents_updated_at on public.payment_intents;
create trigger update_payment_intents_updated_at
  before update on public.payment_intents
  for each row
  execute function public.update_updated_at_column();

alter table public.payment_intents enable row level security;

-- Merchants can SELECT their own payment intents.
drop policy if exists "payment_intents_select_own_merchant" on public.payment_intents;
create policy "payment_intents_select_own_merchant"
  on public.payment_intents
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.merchants m
      where m.id = payment_intents.merchant_id
        and m.profile_id = auth.uid()
    )
  );

-- Merchants can INSERT intents for their own merchant id.
drop policy if exists "payment_intents_insert_own_merchant" on public.payment_intents;
create policy "payment_intents_insert_own_merchant"
  on public.payment_intents
  for insert
  to authenticated
  with check (
    exists (
      select 1
      from public.merchants m
      where m.id = payment_intents.merchant_id
        and m.profile_id = auth.uid()
    )
  );

-- Merchants can UPDATE their own intents (useful for cancel flows).
-- If you prefer updates ONLY from backend service role, remove this policy.
drop policy if exists "payment_intents_update_own_merchant" on public.payment_intents;
create policy "payment_intents_update_own_merchant"
  on public.payment_intents
  for update
  to authenticated
  using (
    exists (
      select 1
      from public.merchants m
      where m.id = payment_intents.merchant_id
        and m.profile_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.merchants m
      where m.id = payment_intents.merchant_id
        and m.profile_id = auth.uid()
    )
  );

commit;
