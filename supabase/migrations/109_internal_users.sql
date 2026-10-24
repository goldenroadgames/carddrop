-- Staff accounts for the admin site (replaces the single shared ADMIN_PASSWORD).
--
-- Staff sign in through Supabase Auth (email + password + authenticator-app code).
-- Being in auth.users is NOT enough: every app user is in auth.users too. Admin
-- access requires an ACTIVE row in internal_users, written only by the server
-- (service role). RLS is on with no policies, so the app's anon/authenticated
-- keys can never read or change it.
--
-- Roles: manager (everything, manages staff), compliance, marketing, finance.
-- What each role may do lives in admin_role_permissions, so it can be changed
-- without a deploy. The web code checks permissions, never role names.

create table if not exists internal_users (
  auth_user_id uuid primary key references auth.users (id) on delete cascade,
  email        text not null,
  role         text not null check (role in ('manager', 'compliance', 'marketing', 'finance')),
  active       boolean not null default true,
  invited_by   uuid references internal_users (auth_user_id) on delete set null,
  created_at   timestamptz not null default now()
);

create unique index if not exists internal_users_email_idx on internal_users (lower(email));

alter table internal_users enable row level security;
revoke all on internal_users from anon, authenticated;

create table if not exists admin_role_permissions (
  role       text not null check (role in ('manager', 'compliance', 'marketing', 'finance')),
  permission text not null,
  primary key (role, permission)
);

alter table admin_role_permissions enable row level security;
revoke all on admin_role_permissions from anon, authenticated;

-- Permissions:
--   staff.manage       invite / disable staff, change roles, reset authenticators
--   cards.moderate     report a card, legal hold, reported-cards + legal-holds pages
--   appeals.review     appeals page
--   suspensions.manage suspended-accounts page
--   held.view          unlock held-card pictures (also needs a fresh authenticator code)
--   marketing.curate   Add / Manage Marketing Cards
--   promo.manage       promo codes
insert into admin_role_permissions (role, permission) values
  ('manager', 'staff.manage'),
  ('manager', 'cards.moderate'),
  ('manager', 'appeals.review'),
  ('manager', 'suspensions.manage'),
  ('manager', 'held.view'),
  ('manager', 'marketing.curate'),
  ('manager', 'promo.manage'),
  ('compliance', 'cards.moderate'),
  ('compliance', 'appeals.review'),
  ('compliance', 'suspensions.manage'),
  ('compliance', 'held.view'),
  ('marketing', 'marketing.curate'),
  ('finance', 'promo.manage')
on conflict do nothing;

-- Limits (minutes / hours), edited here, no deploy needed.
insert into zz_config (key, value, description) values
  ('admin_session_idle_minutes', '30', 'Staff are signed out of the admin site after this many minutes with no activity.'),
  ('admin_session_max_hours', '8', 'Staff are signed out of the admin site this many hours after signing in, however active.'),
  ('admin_held_unlock_minutes', '15', 'Held-card pictures stay unlocked this many minutes after a fresh authenticator code.'),
  ('admin_marketing_all_unlock_minutes', '60', 'Marketing staff: "Show all cards" stays unlocked at most this many minutes after a fresh authenticator code.'),
  ('admin_marketing_all_idle_minutes', '10', 'Marketing staff: "Show all cards" locks again after this many minutes with no activity (leaving the marketing pages also locks it).')
on conflict (key) do nothing;

-- FIRST MANAGER (run once by hand AFTER creating yourself in Supabase Auth:
-- Dashboard > Authentication > Users > Add user, with "Auto Confirm User" on).
-- Replace the email, then run:
--
--   insert into internal_users (auth_user_id, email, role)
--   select id, email, 'manager' from auth.users where lower(email) = lower('you@yourdomain.com');
