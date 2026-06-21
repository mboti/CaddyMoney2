-- Allow standard authenticated users to read limited merchant info (business_name)
-- for merchants they have transacted with as the payer (user -> merchant).
--
-- Without this, the app cannot display merchant names in the user's Transactions → Paid list,
-- because `public.merchants` is protected by RLS (only the merchant themselves + admins).

-- Note: This grants row visibility, not column-level permissions. If you later add sensitive
-- fields to `merchants`, consider exposing a `public_merchants` view instead.

drop policy if exists "Users can view merchants they paid" on public.merchants;
create policy "Users can view merchants they paid"
  on public.merchants
  for select
  to authenticated
  using (
    public.is_admin(auth.uid())
    or auth.uid() = profile_id
    or exists (
      select 1
      from public.transactions t
      where t.sender_profile_id = auth.uid()
        and t.receiver_merchant_id = public.merchants.id
    )
  );
