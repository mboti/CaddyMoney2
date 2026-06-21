-- Fix: uuid_generate_v4() does not exist
-- Some projects don’t have the uuid-ossp extension enabled by default.
-- Our schema + RPCs rely on uuid_generate_v4() for primary keys and transaction IDs.

begin;

create extension if not exists "uuid-ossp";

-- Also enable pgcrypto for gen_random_uuid() (handy for future migrations).
create extension if not exists "pgcrypto";

commit;
