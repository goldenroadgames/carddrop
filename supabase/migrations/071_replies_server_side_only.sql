-- Web replies now go through the submit-reply edge function (moderation +
-- rate limit, then it uploads the photo and inserts the reply with the
-- service role). Remove the two anonymous write paths so nothing can skip it:
--   * anyone could upload any file to the reply-photos bucket
--   * anyone could insert any row into replies
-- Public photo URLs keep working (public bucket). The sender's own select /
-- update policies on replies are untouched.
--
-- RUN ONLY AFTER the submit-reply function is deployed AND the web change is
-- live, or replying will fail.
--
-- Rollback:
--   create policy "reply-photos: anon can upload" on storage.objects
--     for insert to anon with check (bucket_id = 'reply-photos');
--   create policy "replies: anyone inserts" on replies
--     for insert with check (true);

drop policy if exists "reply-photos: anon can upload" on storage.objects;
drop policy if exists "replies: anyone inserts" on replies;
