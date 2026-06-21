-- Adds structured merchant onboarding + KYC fields.
-- Safe to run multiple times.

alter table public.merchants
  add column if not exists owner_first_name text,
  add column if not exists owner_last_name text,
  add column if not exists categories text[] not null default '{}',
  add column if not exists country_name text,
  add column if not exists business_type text,
  add column if not exists vat_number text,
  add column if not exists date_of_birth date,
  add column if not exists nationality text,
  add column if not exists iban text,
  add column if not exists account_holder_name text,
  add column if not exists customer_support_address text,
  add column if not exists id_document_path text,
  add column if not exists proof_of_address_path text,
  add column if not exists business_registration_doc_path text,
  add column if not exists sms_verified boolean not null default false,
  add column if not exists profile_completed boolean not null default false,
  add column if not exists profile_completed_at timestamptz;

-- Keep legacy business_category for now, but encourage using categories.
