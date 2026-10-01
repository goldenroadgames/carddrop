-- Codify the RLS state that already exists live on card_recipients (added via
-- dashboard, never captured in a migration), and relax the insert check so it
-- no longer requires auth.uid() to still match cards.sender_id at send time.
-- Anonymous Supabase sessions aren't guaranteed to keep the same auth.uid()
-- between card creation and send (app restart, session refresh, etc.), so the
-- old check silently dropped the recipient row via the client's `try?` insert
-- while still marking the card sent.

alter table card_recipients enable row level security;

drop policy if exists "sender insert card recipients" on card_recipients;
create policy "sender insert card recipients"
  on card_recipients
  for insert
  to authenticated
  with check (
    card_id in (select cards.id from cards)
  );

drop policy if exists "service role full access" on card_recipients;
create policy "service role full access"
  on card_recipients
  for all
  to service_role
  using (true)
  with check (true);
