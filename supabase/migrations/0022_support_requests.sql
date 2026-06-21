-- Support requests / tickets

begin;

create table if not exists public.support_requests (
  id uuid primary key default gen_random_uuid(),
  ticket_number text not null unique,
  requester_type text not null check (requester_type in ('user', 'merchant')),
  requester_profile_id uuid not null references public.profiles(id) on delete cascade,
  subject text not null,
  description text not null,
  status text not null default 'new' check (status in ('new', 'in_progress', 'resolved')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_support_requests_requester_profile_id on public.support_requests(requester_profile_id);
create index if not exists idx_support_requests_status on public.support_requests(status);
create index if not exists idx_support_requests_created_at on public.support_requests(created_at desc);

do $$
begin
  if exists (select 1 from pg_proc where proname = 'update_updated_at_column') then
    if not exists (select 1 from pg_trigger where tgname = 'update_support_requests_updated_at') then
      create trigger update_support_requests_updated_at
        before update on public.support_requests
        for each row
        execute function public.update_updated_at_column();
    end if;
  end if;
end $$;

alter table public.support_requests enable row level security;

-- Users & merchants: can create support requests.
do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'support_requests' and policyname = 'support_requests_insert_own') then
    create policy support_requests_insert_own
      on public.support_requests
      for insert
      to authenticated
      with check (requester_profile_id = auth.uid());
  end if;
end $$;

-- Users & merchants: can read their own requests.
do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'support_requests' and policyname = 'support_requests_select_own') then
    create policy support_requests_select_own
      on public.support_requests
      for select
      to authenticated
      using (requester_profile_id = auth.uid());
  end if;
end $$;

-- Admins: can read all requests.
do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'support_requests' and policyname = 'support_requests_select_admin') then
    create policy support_requests_select_admin
      on public.support_requests
      for select
      to authenticated
      using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));
  end if;
end $$;

-- Admins: can update status.
do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'support_requests' and policyname = 'support_requests_update_admin') then
    create policy support_requests_update_admin
      on public.support_requests
      for update
      to authenticated
      using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
      with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));
  end if;
end $$;

commit;
