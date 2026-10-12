-- A device where a FINAL suspension happened is marked permanent. A new account
-- created on such a device is marked final automatically (no appeal), so the
-- person lands on the minimal "Account Disabled" screen. Set when an admin
-- makes a suspension final, and by the sweeper for suspensions that became
-- final by count (and before it deletes the account's data: deleting the users
-- row clears user_devices.user_id, so the device must be marked first).
alter table user_devices add column if not exists permanent boolean not null default false;

-- Asked by the app BEFORE any account exists (signed out), so a permanently
-- disabled phone opens straight onto the Account Disabled screen instead of the
-- sign-in screen. Callable without a login; it reveals only whether a random
-- device id is flagged. Unknown devices answer false.
create or replace function device_is_permanent(p_device uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select coalesce((select permanent from user_devices where device_uuid = p_device), false);
$$;
revoke all on function device_is_permanent(uuid) from public;
grant execute on function device_is_permanent(uuid) to anon, authenticated;

-- Reinstating an account also clears "permanent" on its devices (an admin who
-- reinstates a final suspension means it). Same function as 062 plus that.
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
  set banned = false, banned_at = null, ban_reason = null, permanent = false
  where user_id = p_user_id;

  update user_notices
  set seen_at = now()
  where user_id = p_user_id
    and kind = 'ban'
    and seen_at is null;
end;
$$;
revoke all on function unban_account(uuid) from public, anon, authenticated;
