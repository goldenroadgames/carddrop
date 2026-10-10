-- Soft-delete marker for cards. Null = live. A timestamp means the sender
-- deleted the card at that moment: the shared link/web page stops working and
-- the card disappears from the app, and a server-side purge (to be built, after
-- the retention policy is settled) removes files and rows once the grace
-- period has passed. Nothing reads or writes this column yet.
--
-- Not writable from the client: cards has no UPDATE policy, so marking a card
-- will go through an Edge Function / RPC, not a direct table update.

alter table cards
  add column if not exists deleted_at timestamptz;

-- The purge job looks up marked cards past the grace period.
create index if not exists cards_deleted_at_idx
  on cards (deleted_at)
  where deleted_at is not null;
