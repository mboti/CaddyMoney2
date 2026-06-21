-- CaddyMoney development seed data
--
-- Notes:
-- 1) In hosted Supabase, inserting into auth.users directly is typically restricted.
--    In local Supabase / SQL editor with sufficient privileges, this may work.
-- 2) If auth inserts fail, create these users via the Auth panel first, then rerun
--    the profile/merchant/transaction inserts (they are idempotent).

begin;

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- Create 3 demo users (admin, standard user, merchant user)
-- -----------------------------------------------------------------------------

do $$
declare
  admin_id uuid := '11111111-1111-1111-1111-111111111111';
  user_id uuid := '22222222-2222-2222-2222-222222222222';
  merchant_profile_id uuid := '33333333-3333-3333-3333-333333333333';
begin
  -- Best-effort auth user creation (may fail on hosted projects depending on privileges)
  begin
    insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values
      (admin_id, 'authenticated', 'authenticated', 'admin@caddymoney.dev', crypt('password123', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Caddy Admin","role":"admin","preferred_language":"fr"}', now(), now()),
      (user_id, 'authenticated', 'authenticated', 'user@caddymoney.dev', crypt('password123', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Jean Dupont","role":"standardUser","preferred_language":"fr"}', now(), now()),
      (merchant_profile_id, 'authenticated', 'authenticated', 'merchant@caddymoney.dev', crypt('password123', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{"full_name":"Amina Merchant","role":"merchant","preferred_language":"fr"}', now(), now())
    on conflict (id) do nothing;
  exception
    when others then
      -- Ignore if auth schema is locked down.
      null;
  end;

  -- Profiles (also created by trigger when auth.users insert succeeds)
  insert into public.profiles (id, full_name, email, role, status, preferred_language)
  values
    (admin_id, 'Caddy Admin', 'admin@caddymoney.dev', 'admin', 'active', 'fr'),
    (user_id, 'Jean Dupont', 'user@caddymoney.dev', 'standardUser', 'active', 'fr'),
    (merchant_profile_id, 'Amina Merchant', 'merchant@caddymoney.dev', 'merchant', 'active', 'fr')
  on conflict (id) do update
    set full_name = excluded.full_name,
        email = excluded.email,
        role = excluded.role,
        status = excluded.status,
        preferred_language = excluded.preferred_language;

  -- Ensure each profile has a user wallet (trigger should do it, but keep seed idempotent)
  insert into public.wallets (owner_type, profile_id, currency_code, balance)
  values
    ('user', user_id, 'EUR', 250.00),
    ('user', merchant_profile_id, 'EUR', 100.00)
  on conflict do nothing;

  -- Merchant application + approval
  insert into public.merchants (
    profile_id, unique_merchant_id, business_name, owner_name, business_email, business_phone,
    city, country_code, business_category, status, approved_by, approved_at
  )
  values (
    merchant_profile_id, 'MCH-000001', 'Caddy Café', 'Amina Merchant', 'merchant@caddymoney.dev', '+33 6 00 00 00 00',
    'Paris', 'FR', 'Cafe', 'approved', admin_id, now()
  )
  on conflict (unique_merchant_id) do update
    set status = excluded.status,
        approved_by = excluded.approved_by,
        approved_at = excluded.approved_at;

  -- Ensure merchant wallet exists (trigger should do it, but keep seed idempotent)
  insert into public.wallets (owner_type, merchant_id, currency_code, balance)
  select 'merchant', m.id, 'EUR', 50.00
  from public.merchants m
  where m.unique_merchant_id = 'MCH-000001'
  on conflict do nothing;

end $$;

commit;

-- -----------------------------------------------------------------------------
-- Coupons (optional dev helper)
-- -----------------------------------------------------------------------------
-- If you want a sample coupon for the currently authenticated user, run this
-- manually in the SQL editor while logged in as that user:
--
-- insert into public.coupons(profile_id, title, category, currency_code, balance)
-- values (auth.uid(), 'Healthcare', 'Healthcare', 'EUR', 50.00);
