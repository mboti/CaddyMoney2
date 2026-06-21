-- Add first_name / last_name / username to profiles and generate unique username

begin;

alter table public.profiles
  add column if not exists first_name text,
  add column if not exists last_name text,
  add column if not exists username text;

create unique index if not exists idx_profiles_username_unique on public.profiles(username);

-- Generate a unique username based on first + last name.
-- Example: johnsmith, johnsmith2, johnsmith3 ...
create or replace function public.generate_unique_username(p_first_name text, p_last_name text)
returns text
language plpgsql
as $$
declare
  base text;
  candidate text;
  i int;
begin
  base := lower(regexp_replace(coalesce(p_first_name, '') || coalesce(p_last_name, ''), '[^a-z0-9]+', '', 'g'));
  if base is null or base = '' then
    base := 'user';
  end if;

  candidate := base;
  i := 0;
  while exists (select 1 from public.profiles p where p.username = candidate) loop
    i := i + 1;
    candidate := base || i::text;
  end loop;

  return candidate;
end;
$$;

-- Update the auth->profiles trigger to store first/last and auto-username.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  fn text;
  ln text;
  uname text;
begin
  fn := nullif(trim(coalesce(new.raw_user_meta_data->>'first_name', '')), '');
  ln := nullif(trim(coalesce(new.raw_user_meta_data->>'last_name', '')), '');
  uname := public.generate_unique_username(fn, ln);

  insert into public.profiles (id, full_name, email, role, phone, preferred_language, first_name, last_name, username)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data->>'full_name', ''), trim(coalesce(fn, '') || ' ' || coalesce(ln, ''))),
    new.email,
    coalesce((new.raw_user_meta_data->>'role')::public.app_role, 'standardUser'),
    coalesce(new.raw_user_meta_data->>'phone', null),
    coalesce(new.raw_user_meta_data->>'preferred_language', 'fr'),
    fn,
    ln,
    uname
  )
  on conflict (id) do nothing;
  return new;
exception
  when others then
    -- Never block auth signups if profile creation fails.
    return new;
end;
$$;

-- Backfill existing rows (best-effort) where username is null.
update public.profiles p
set username = public.generate_unique_username(
  split_part(p.full_name, ' ', 1),
  nullif(trim(substr(p.full_name, length(split_part(p.full_name, ' ', 1)) + 2)), '')
)
where p.username is null;

commit;
