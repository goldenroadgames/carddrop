-- Cards are created only by the send-card edge function (service role), which
-- runs the ban check, send limits and content-safety gate. "cards: insert own"
-- let any authenticated session, including a free anonymous one, insert a
-- cards row directly and so publish a /card/<id> link with none of those
-- checks. The iOS app only reads cards, so nothing depends on this policy.
--
-- Rollback:
--   create policy "cards: insert own" on cards for insert
--     with check (auth.uid() = sender_id);

drop policy if exists "cards: insert own" on cards;
