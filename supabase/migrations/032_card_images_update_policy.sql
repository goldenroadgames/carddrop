-- 019_card_images_bucket.sql only granted INSERT + SELECT on storage.objects
-- for the card-images bucket — no UPDATE policy. upload(..., upsert: true)
-- performs an actual row UPDATE when the object already exists (not a plain
-- insert), so re-uploading to a path that's already there (e.g. a second
-- physical order for the same card, which re-uploads its digital-resolution
-- images) was silently blocked by RLS: "new row violates row-level security
-- policy". A card's content is immutable once created (a new design always
-- gets a new cardID), so an overwrite is always identical bytes — this just
-- grants the storage layer permission to actually perform it.
create policy "card-images: auth users can update"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'card-images')
  with check (bucket_id = 'card-images');
