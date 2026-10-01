-- CardDrop user_devices and ban_reviews tables
-- Run AFTER 001_schema.sql and 002_rls.sql
--
-- Replaces the single device_uuid column on users with a proper
-- user_devices table supporting multiple devices per account,
-- per-device banning, and ban review requests.

-- ============================================================
-- SCHEMA CHANGES
-- ============================================================

-- Drop single device_uuid from users (replaced by user_devices)
alter table users drop column if exists device_uuid;

-- One row per physical device. user_id is nullable to support
-- the window between Keychain UUID creation and account linkage,
-- though in practice it is always set before writing to Supabase.
create table user_devices (
  device_uuid   uuid primary key,
  user_id       uuid references users(id) on delete set null,
  created_at    timestamptz not null default now(),
  banned        boolean not null default false,
  banned_at     timestamptz,
  ban_reason    text
);

-- Fast lookup of all devices for a given account
create index on user_devices(user_id);

-- Ban review requests submitted from within the app.
-- resolved_at / resolution are set by the developer after review.
create table ban_reviews (
  id            uuid primary key default gen_random_uuid(),
  device_uuid   uuid not null references user_devices(device_uuid),
  user_id       uuid references users(id) on delete set null,
  message       text,
  created_at    timestamptz not null default now(),
  resolved_at   timestamptz,
  resolution    text
);

-- ============================================================
-- RLS
-- ============================================================

alter table user_devices enable row level security;
alter table ban_reviews enable row level security;

-- user_devices: app can read its own device rows
create policy "user_devices: read own"
  on user_devices for select
  using (auth.uid() = user_id);

-- user_devices: app can register a new device
create policy "user_devices: insert own"
  on user_devices for insert
  with check (auth.uid() = user_id);

-- No client update policy — banned flag is set via service role only
-- (Supabase dashboard SQL editor or edge functions using service role key)

-- ban_reviews: app can submit a review request
create policy "ban_reviews: insert own"
  on ban_reviews for insert
  with check (auth.uid() = user_id);

-- ban_reviews: app can read its own review requests
create policy "ban_reviews: read own"
  on ban_reviews for select
  using (auth.uid() = user_id);
