-- card_recipients had RLS enabled (015) with an insert policy but no select
-- policy for authenticated/anon roles, so PostgREST silently returned zero
-- rows for CardRecipientService.fetchHistory, making SentCardDetailSheet show
-- "No send record found for this card." even though rows existed.
--
-- Mirrors the relaxed insert check (015): don't require auth.uid() to still
-- match cards.sender_id, since anonymous sessions aren't guaranteed to keep
-- the same auth.uid() between card creation and later viewing.

drop policy if exists "sender select card recipients" on card_recipients;
create policy "sender select card recipients"
  on card_recipients
  for select
  to authenticated
  using (
    card_id in (select cards.id from cards)
  );
