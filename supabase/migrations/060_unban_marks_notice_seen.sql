-- Reinstating an account must not leave its "Account Suspended" notice
-- waiting: the suspended person never saw it (the Suspended screen replaced
-- the app), so after reinstatement My Cards would pop it up. Mark unseen ban
-- notices as seen when the account is reinstated. Everything else in
-- unban_account is unchanged from 056.
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

  update user_notices
  set seen_at = now()
  where user_id = p_user_id
    and kind = 'ban'
    and seen_at is null;
end;
$$;

revoke all on function unban_account(uuid) from public, anon, authenticated;
