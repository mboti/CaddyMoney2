-- Add optional coordinates for merchant location.
--
-- Used by the admin "Manage Merchants" detail screen to show a map preview and
-- allow manual correction of the marker position.

alter table public.merchants
  add column if not exists latitude double precision,
  add column if not exists longitude double precision;

-- Optional: quick filter by having coords.
create index if not exists merchants_lat_lng_idx
  on public.merchants (latitude, longitude);
