-- Run ONLY after submit-reaction is deployed AND the web change using it is
-- live (and 071 has run). Run 11Oct26.
--
-- Emoji reactions now go through the submit-reaction edge function, which
-- enforces the sender's "replies off" switch. Remove the anonymous direct insert.
--
-- Rollback:
--   create policy "reactions: anyone inserts" on reactions
--     for insert with check (true);

drop policy if exists "reactions: anyone inserts" on reactions;
