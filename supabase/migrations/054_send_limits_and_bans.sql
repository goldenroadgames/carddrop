-- Step 2 of carddrop/card_delete_complaints_bans_plan.md: send caps by device
-- and account-level bans. Run AFTER 053.

-- ------------------------------------------------------------------
-- 1. Caps: anonymous and unverified are the same, 5/month + 15 lifetime,
--    enforced by account AND by device (stricter wins) in send-card.
-- ------------------------------------------------------------------
insert into zz_config (key, value, description) values
  ('send_limit_anonymous_monthly',  '5',  'Monthly digital sends for anonymous (no account) users (also enforced per device)'),
  ('send_limit_anonymous_lifetime', '15', 'Lifetime digital sends for anonymous users (also enforced per device)'),
  ('send_limit_unverified_monthly', '5',  'Monthly digital sends for unverified (email on file, no OTP) users (also enforced per device)'),
  ('send_limit_unverified_lifetime','15', 'Lifetime digital sends for unverified users (also enforced per device)')
on conflict (key) do update set value = excluded.value, description = excluded.description;

-- ------------------------------------------------------------------
-- 2. Per-device send counters. month_key ('YYYY-MM', UTC) lets the monthly
--    count reset itself without a cron job.
-- ------------------------------------------------------------------
alter table user_devices
  add column if not exists sends_this_month int  not null default 0,
  add column if not exists sends_lifetime   int  not null default 0,
  add column if not exists month_key        text;

-- The sending device is recorded on each card so complaints can later be
-- counted per device.
alter table cards add column if not exists device_uuid uuid;

-- ------------------------------------------------------------------
-- 3. Account bans. No FK on user_id so a ban survives account deletion;
--    email is the lowercase VERIFIED email only (an unverified email proves
--    nothing). RLS on with no policies = service role only.
-- ------------------------------------------------------------------
create table if not exists account_bans (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid unique,   -- plain unique (nulls allowed) so PostgREST upserts can target it
  email       text,
  reason      text,
  created_at  timestamptz not null default now()
);

create index if not exists account_bans_email_idx
  on account_bans (email) where email is not null;

alter table account_bans enable row level security;

-- Bans an account and every device linked to it. Records the verified email
-- (if any) so the ban survives account deletion/re-registration. Run it from
-- the SQL editor:   select ban_account('<user uuid>', 'harassment');
create or replace function ban_account(p_user_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  select lower(u.email) into v_email
  from auth.users u
  where u.id = p_user_id
    and (
      u.raw_app_meta_data ->> 'send_unlocked' = 'true'
      or exists (select 1 from auth.identities i where i.user_id = u.id and i.provider = 'apple')
    );

  insert into account_bans (user_id, email, reason)
  values (p_user_id, v_email, p_reason)
  on conflict (user_id) do nothing;

  update user_devices
  set banned = true,
      banned_at = now(),
      ban_reason = coalesce(p_reason, 'account banned')
  where user_id = p_user_id and not banned;
end;
$$;

revoke all on function ban_account(uuid, text) from public, anon, authenticated;
