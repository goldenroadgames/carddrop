-- Reinstating an account no longer clears its strikes. A reinstated account
-- keeps its complaint history, so if it already had the strike limit the very
-- next report suspends it again. (Complaints the owner decides were unfair can
-- still be cleared one by one: update card_complaints set cleared_at = now()
-- where card_id = '<card>'.) Replaces 056/060; everything else is unchanged:
-- bans removed, devices unbanned, unseen suspension notice marked seen.
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
