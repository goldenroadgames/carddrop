-- Two holes found in the 11Oct26 policy audit.
--
-- 1. card_recipients: "sender select card recipients" was
--    card_id IN (SELECT id FROM cards). cards has a public-read policy
--    (using true), so that subquery returned EVERY card to every user and any
--    authenticated (incl. anonymous sign-in) client could read all recipient
--    names/emails/phones/addresses. Scope both policies to the caller's own
--    cards. The app only reads/inserts rows for its own card; the edge
--    functions and admin pages use the service role (own policy, untouched).
--
-- 2. user_devices: two dashboard-made policies ("authenticated update
--    user_devices" / "authenticated upsert user_devices") were using true /
--    check true, so any client could update ANY device row, including
--    banned/banned_at/ban_reason and the send counters (un-ban a device,
--    reset the send caps, ban everyone). The app only upserts
--    (device_uuid, user_id) (UserService.swift). Send counters and bans are
--    written by edge functions / admin pages with the service role.
--    Keep the upsert working but limit what a client can write to those two
--    columns. A device may be claimed by a new account on the same phone, so
--    UPDATE stays open by row but the new user_id must be the caller's.

-- ------------------------------------------------------------------
-- 1. card_recipients
-- ------------------------------------------------------------------
drop policy if exists "sender select card recipients" on card_recipients;
drop policy if exists "sender insert card recipients" on card_recipients;

create policy "sender select card recipients"
  on card_recipients for select
  to authenticated
  using (exists (
    select 1 from cards c
    where c.id = card_recipients.card_id and c.sender_id = auth.uid()
  ));

create policy "sender insert card recipients"
  on card_recipients for insert
  to authenticated
  with check (exists (
    select 1 from cards c
    where c.id = card_recipients.card_id and c.sender_id = auth.uid()
  ));

-- ------------------------------------------------------------------
-- 2. user_devices
-- ------------------------------------------------------------------
drop policy if exists "authenticated update user_devices" on user_devices;
drop policy if exists "authenticated upsert user_devices" on user_devices;

create policy "user_devices: claim device"
  on user_devices for update
  to authenticated
  using (true)
  with check (user_id = auth.uid());

-- Column privileges (RLS can't limit columns). Clients keep only the two
-- columns the app writes; everything else is service-role only.
revoke insert, update, delete, truncate on user_devices from anon;
revoke insert, update, delete, truncate on user_devices from authenticated;
grant insert (device_uuid, user_id) on user_devices to authenticated;
grant update (device_uuid, user_id) on user_devices to authenticated;
