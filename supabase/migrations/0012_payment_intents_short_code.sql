-- Adds a human-friendly short code for manual typing of payment intent tokens.

alter table public.payment_intents
  add column if not exists short_code text;

-- Enforce uniqueness only when present (keeps backward compatibility for existing rows).
create unique index if not exists payment_intents_short_code_unique
  on public.payment_intents (short_code)
  where short_code is not null;
