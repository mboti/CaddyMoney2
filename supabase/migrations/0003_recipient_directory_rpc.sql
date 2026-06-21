-- RPC helpers for recipient discovery under RLS.
--
-- Problem:
-- - profiles RLS allows users to read only their own profile.
-- - Recipient management needs to discover other users by email/name and list saved recipients with recipient info.
--
-- Solution:
-- - SECURITY DEFINER functions that return only limited, non-sensitive fields.
-- - Access restricted to authenticated users.

create or replace function public.find_active_profiles(p_identifier text, p_limit int default 10)
returns table (
  id uuid,
  email text,
  full_name text
)
language sql
security definer
set search_path = public
as $$
  select p.id, p.email, p.full_name
  from public.profiles p
  where p.status = 'active'
    and (
      lower(p.email) = lower(trim(p_identifier))
      or p.full_name ilike ('%' || trim(p_identifier) || '%')
    )
  order by p.created_at desc
  limit greatest(1, least(p_limit, 25));
$$;

grant execute on function public.find_active_profiles(text, int) to authenticated;

create or replace function public.list_my_recipients(p_limit int default 50)
returns table (
  owner_user_id uuid,
  recipient_user_id uuid,
  recipient_email text,
  recipient_full_name text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    ur.owner_user_id,
    ur.recipient_user_id,
    p.email as recipient_email,
    p.full_name as recipient_full_name,
    ur.created_at
  from public.user_recipients ur
  join public.profiles p on p.id = ur.recipient_user_id
  where ur.owner_user_id = auth.uid()
  order by ur.created_at desc
  limit greatest(1, least(p_limit, 200));
$$;

grant execute on function public.list_my_recipients(int) to authenticated;
