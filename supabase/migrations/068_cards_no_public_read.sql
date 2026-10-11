-- "cards: public read by id" was using (true), so anyone holding the anon key
-- (compiled into the app) could list every card: sender_id, device_uuid,
-- message_preview, nicknames, ink messages, reported_at, deleted_at.
-- The web /card/[id], /reply and /report pages now read cards with the
-- service role (createSupabaseAdmin), which bypasses RLS. The iOS app only
-- reads its own cards, covered by "cards: sender reads own" (kept).
--
-- Run AFTER the web change is deployed, or the card pages will 404.
--
-- Rollback:
--   create policy "cards: public read by id" on cards for select using (true);

drop policy if exists "cards: public read by id" on cards;
