-- card-holding: server-only scratch bucket used by _shared/cardImages.ts.
-- Staged files (client-writable) are first copied here, moderated here, and
-- only then promoted to card-images / card-private, so the bytes that were
-- checked can't be swapped by the client before they are published.
-- PRIVATE with deliberately NO storage.objects policies: only the service
-- role can read or write it. Files live here only for the length of one
-- send-card / submit-to-lob call and are removed at the end of it.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('card-holding', 'card-holding', false, 15728640, array['image/jpeg'])
on conflict (id) do nothing;
