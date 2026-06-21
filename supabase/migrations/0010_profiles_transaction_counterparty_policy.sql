-- Allow users to see the profile of the *other* person involved in their transactions.
-- This is required for PostgREST embedded selects like:
--   select *, sender:sender_profile_id(...), receiver:receiver_profile_id(...)
-- Without this, RLS on public.profiles will return null for joined sender/receiver.

drop policy if exists "Users can view transaction counterparty profiles" on public.profiles;
create policy "Users can view transaction counterparty profiles"
  on public.profiles
  for select
  to authenticated
  using (
    public.is_admin(auth.uid())
    or auth.uid() = id
    or exists (
      select 1
      from public.transactions t
      where (
        (t.sender_profile_id = auth.uid() and t.receiver_profile_id = public.profiles.id)
        or (t.receiver_profile_id = auth.uid() and t.sender_profile_id = public.profiles.id)
      )
    )
  );
