-- CardDrop remote config table
-- Run AFTER 001_schema.sql and 002_rls.sql
--
-- Stores tunable app configuration so limits can be changed
-- without an app release. Edge functions and iOS app both read
-- from this table. Only the developer can write (service role).

-- ============================================================
-- TABLE
-- ============================================================

create table config (
  key         text primary key,
  value       text not null,
  description text  -- human-readable note for developer reference
);

-- ============================================================
-- SEED VALUES
-- ============================================================

insert into config (key, value, description) values
  ('send_limit_anonymous_monthly',   '2',  'Monthly digital sends for anonymous (no account) users'),
  ('send_limit_anonymous_lifetime',  '10', 'Lifetime digital sends for anonymous users before account required'),
  ('send_limit_unverified_monthly',  '5',  'Monthly digital sends for unverified (email on file, no OTP) users'),
  ('send_limit_unverified_lifetime', '-1', 'Lifetime digital sends for unverified users (-1 = unlimited)'),
  ('send_limit_verified_monthly',    '-1', 'Monthly digital sends for OTP-verified users (-1 = unlimited)'),
  ('send_limit_verified_lifetime',   '-1', 'Lifetime digital sends for OTP-verified users (-1 = unlimited)'),
  ('send_limit_unlimited_monthly',   '-1', 'Monthly digital sends for unlimited (paid) tier (-1 = unlimited)'),
  ('send_limit_unlimited_lifetime',  '-1', 'Lifetime digital sends for unlimited (paid) tier (-1 = unlimited)');

-- ============================================================
-- RLS
-- ============================================================

alter table config enable row level security;

-- Anyone can read config (app and edge functions need this, nothing sensitive here)
create policy "config: public read"
  on config for select
  using (true);

-- No client writes — values are changed via Supabase SQL editor (service role only)
