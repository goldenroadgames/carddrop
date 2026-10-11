-- 019/032 let ANY authenticated user (including anonymous sign-ins) insert or
-- update ANY path in the card-images bucket, so one user could overwrite
-- another user's card images. The app only ever writes to
-- card-images/{senderID.lowercased()}/..., so restrict writes to the caller's
-- own folder. Public read and the "users select own objects" policy are
-- untouched; deletes run server-side with the service role.

drop policy if exists "card-images: auth users can upload" on storage.objects;
drop policy if exists "card-images: auth users can update" on storage.objects;

create policy "card-images: auth users can upload"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'card-images'
    and (storage.foldername(name))[1] = lower(auth.uid()::text)
  );

create policy "card-images: auth users can update"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'card-images'
    and (storage.foldername(name))[1] = lower(auth.uid()::text)
  )
  with check (
    bucket_id = 'card-images'
    and (storage.foldername(name))[1] = lower(auth.uid()::text)
  );
