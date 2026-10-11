-- "reply-photos: public read" let anyone with the anon key list and download
-- every reply photo through the storage API. The bucket is public, so the
-- /storage/v1/object/public/... URLs stored in replies.reply_image_url (and
-- shown on the web and in the app) work without any SELECT policy.
-- "reply-photos: anon can upload" is untouched; size / type limits are set on
-- the bucket itself (dashboard: 5 MB, image/jpeg only — the web page always
-- uploads a resized JPEG).
--
-- Rollback:
--   create policy "reply-photos: public read" on storage.objects
--     for select using (bucket_id = 'reply-photos');

drop policy if exists "reply-photos: public read" on storage.objects;
