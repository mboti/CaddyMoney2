-- Saved recipients: link an owner user to a recipient user.
-- This enables a “saved recipient list” on Send Money.

create table if not exists public.user_recipients (
  owner_user_id uuid not null,
  recipient_user_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint user_recipients_owner_user_id_fkey foreign key (owner_user_id) references public.profiles (id) on delete cascade,
  constraint user_recipients_recipient_user_id_fkey foreign key (recipient_user_id) references public.profiles (id) on delete cascade,
  constraint user_recipients_no_self check (owner_user_id <> recipient_user_id),
  constraint user_recipients_unique unique (owner_user_id, recipient_user_id)
);

create index if not exists idx_user_recipients_owner on public.user_recipients (owner_user_id, created_at desc);

-- updated_at trigger (uses the function created in 0001_init.sql)
drop trigger if exists set_timestamp on public.user_recipients;
create trigger set_timestamp
before update on public.user_recipients
for each row execute function public.update_updated_at_column();

alter table public.user_recipients enable row level security;

drop policy if exists "user_recipients_select_own" on public.user_recipients;
create policy "user_recipients_select_own"
on public.user_recipients
for select
using (owner_user_id = auth.uid());

drop policy if exists "user_recipients_insert_own" on public.user_recipients;
create policy "user_recipients_insert_own"
on public.user_recipients
for insert
with check (owner_user_id = auth.uid());

drop policy if exists "user_recipients_delete_own" on public.user_recipients;
create policy "user_recipients_delete_own"
on public.user_recipients
for delete
using (owner_user_id = auth.uid());
