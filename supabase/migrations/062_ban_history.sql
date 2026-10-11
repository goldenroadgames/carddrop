-- Keep ban history. Reinstating an account now stamps account_bans.reinstated_at
-- instead of deleting the row, so an account can have several rows over time
-- (one per suspension). A ban is ACTIVE when reinstated_at is null; every check
-- filters on that. Replaces unban_account (061), ban_account (054) and
-- is_suspended (056).

alter table account_bans add column if not exists reinstated_at timestamptz;

-- One ACTIVE ban per account (history rows may repeat).
alter table account_bans drop constraint if exists account_bans_user_id_key;
create unique index if not exists account_bans_active_user_idx
  on account_bans (user_id) where reinstated_at is null;

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
  on conflict (user_id) where reinstated_at is null do nothing;

  update user_devices
  set banned = true,
      banned_at = now(),
      ban_reason = coalesce(p_reason, 'account banned')
  where user_id = p_user_id and not banned;
end;
$$;

revoke all on function ban_account(uuid, text) from public, anon, authenticated;

create or replace function is_suspended(p_device uuid default null)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_email text;
begin
  if v_uid is null then
    return false;
  end if;

  if exists (select 1 from account_bans where user_id = v_uid and reinstated_at is null) then
    return true;
  end if;

  select lower(u.email) into v_email
  from auth.users u
  where u.id = v_uid
    and (
      u.raw_app_meta_data ->> 'send_unlocked' = 'true'
      or exists (select 1 from auth.identities i where i.user_id = u.id and i.provider = 'apple')
    );

  if v_email is not null
     and exists (select 1 from account_bans where email = v_email and reinstated_at is null) then
    return true;
  end if;

  if p_device is not null and exists (select 1 from user_devices where device_uuid = p_device and banned) then
    return true;
  end if;

  if exists (select 1 from user_devices where user_id = v_uid and banned) then
    return true;
  end if;

  return false;
end;
$$;

revoke all on function is_suspended(uuid) from public, anon;
grant execute on function is_suspended(uuid) to authenticated;

-- Reinstates an account: marks its active bans (and any active ban on its
-- verified email) reinstated, unbans its devices, marks its unseen suspension
-- notice seen. Strikes are NOT cleared (061).
create or replace function unban_account(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  select email into v_email
  from account_bans
  where user_id = p_user_id and reinstated_at is null
  order by created_at desc
  limit 1;

  update account_bans
  set reinstated_at = now()
  where reinstated_at is null
    and (user_id = p_user_id or (v_email is not null and email = v_email));

  update user_devices
  set banned = false, banned_at = null, ban_reason = null
  where user_id = p_user_id;

  update user_notices
  set seen_at = now()
  where user_id = p_user_id
    and kind = 'ban'
    and seen_at is null;
end;
$$;

revoke all on function unban_account(uuid) from public, anon, authenticated;
