-- Server-side address book, replacing the local-only JSON address book as
-- the source of truth for the physical-mail (LOB) send flow. Stores email/
-- phone alongside structured mailing-address fields, plus an is_verified
-- cache so a mailing address is only ever sent to LOB's verification
-- endpoint once.

create table user_address_book (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid not null references auth.users(id) on delete cascade,
  nickname           text,               -- informal name shown in picker ("Mom", "Work")
  first_name         text,
  last_name          text,
  street             text,
  city               text,
  state              text,
  zip                text,
  country            text default 'US',
  email              text,
  phone              text,
  is_verified        boolean not null default false,   -- mailing-address verification cache
  verified_at        timestamptz,
  lob_verification_id text,              -- LOB's own verification record id, if useful
  last_used_at       timestamptz not null default now(),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create index on user_address_book(user_id);

alter table user_address_book enable row level security;

-- Owner has full CRUD on their own saved addresses.
create policy "user_address_book: read own"
  on user_address_book for select
  using (auth.uid() = user_id);

create policy "user_address_book: insert own"
  on user_address_book for insert
  with check (auth.uid() = user_id);

create policy "user_address_book: update own"
  on user_address_book for update
  using (auth.uid() = user_id);

create policy "user_address_book: delete own"
  on user_address_book for delete
  using (auth.uid() = user_id);
