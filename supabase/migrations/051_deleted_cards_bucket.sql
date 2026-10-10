-- Holding bucket for the image files of cards a sender has deleted.
--
-- When a card is marked deleted (cards.deleted_at, migration 050), a server-side
-- function moves every file for that card out of the public card-images bucket
-- into here, keeping the same {senderID}/{filename} layout so a restore during
-- the grace period is just a move back. The purge job later removes the files
-- and rows for good.
--
-- PRIVATE and deliberately NO storage.objects policies: with none, clients
-- (anon and authenticated) can neither read nor write anything here; only the
-- service role (Edge Functions) can. Nothing uses this bucket yet.

insert into storage.buckets (id, name, public)
values ('deleted-cards', 'deleted-cards', false)
on conflict (id) do nothing;
