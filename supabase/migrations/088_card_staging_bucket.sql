-- Card images are no longer written to the public card-images bucket by the
-- app. The app uploads to the PRIVATE card-staging bucket; the send-card and
-- submit-to-lob edge functions moderate the staged files and copy the ones
-- that pass into card-images (_shared/cardImages.ts). This closes two holes:
--   * swapping an image after it passed moderation (the app could overwrite
--     its own public file), and
--   * free public image hosting (any session could put files in its own
--     card-images folder).
--
-- card-private holds the print-scale originals (_full, _before_full), which
-- are never moderated and so never public; only the admin marketing copy
-- (service role) reads them. No client policies on it at all.
--
-- RUN THIS LAST: after the new send-card, submit-to-lob, sweep-deleted-cards
-- functions are deployed and the new app build is installed. An older app
-- build can no longer upload once the card-images policies are dropped.
--
-- Rollback: recreate the two card-images policies from 064 and stop using
-- card-staging.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('card-staging', 'card-staging', false, 15728640, array['image/jpeg']),
  ('card-private', 'card-private', false, 15728640, array['image/jpeg'])
on conflict (id) do nothing;

-- The app may write and read back only its own folder of the staging bucket
-- (select is needed for upsert on an existing key). Deletes are server-side.
create policy "card-staging: own folder insert"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'card-staging'
    and (storage.foldername(name))[1] = lower(auth.uid()::text)
  );

create policy "card-staging: own folder update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'card-staging'
    and (storage.foldername(name))[1] = lower(auth.uid()::text)
  )
  with check (
    bucket_id = 'card-staging'
    and (storage.foldername(name))[1] = lower(auth.uid()::text)
  );

create policy "card-staging: own folder select"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'card-staging'
    and (storage.foldername(name))[1] = lower(auth.uid()::text)
  );

-- The app can no longer write the public bucket. Public read and the
-- "users select own objects" read policy are untouched.
drop policy if exists "card-images: auth users can upload" on storage.objects;
drop policy if exists "card-images: auth users can update" on storage.objects;
