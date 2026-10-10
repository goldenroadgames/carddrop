-- Suspended-account gate (carddrop/card_delete_complaints_bans_plan.md, step 4
-- follow-up). Run AFTER 055.

-- Complaints stay on record, but a reinstatement stops them counting toward
-- the next ban.
alter table card_complaints add column if not exists cleared_at timestamptz;

-- The app calls this at launch / on foreground. True if the signed-in
-- account (including anonymous), its VERIFIED email, this device, or any
-- device linked to the account is banned. Mirrors _shared/bans.ts.
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

  if exists (select 1 from account_bans where user_id = v_uid) then
    return true;
  end if;

  select lower(u.email) into v_email
  from auth.users u
  where u.id = v_uid
    and (
      u.raw_app_meta_data ->> 'send_unlocked' = 'true'
      or exists (select 1 from auth.identities i where i.user_id = u.id and i.provider = 'apple')
    );

  if v_email is not null and exists (select 1 from account_bans where email = v_email) then
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

-- Reinstates an account: removes its bans (and the ban on its verified email),
-- unbans its devices, and clears its strikes. Run from the SQL editor:
--   select unban_account('<user uuid>');
create or replace function unban_account(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
begin
  select email into v_email from account_bans where user_id = p_user_id;

  delete from account_bans
  where user_id = p_user_id
     or (v_email is not null and email = v_email);

  update card_complaints
  set cleared_at = now()
  where cleared_at is null
    and (
      sender_id = p_user_id
      or device_uuid in (select device_uuid from user_devices where user_id = p_user_id)
    );

  update user_devices
  set banned = false, banned_at = null, ban_reason = null
  where user_id = p_user_id;
end;
$$;

revoke all on function unban_account(uuid) from public, anon, authenticated;
