-- CardDrop reply-photos storage bucket
-- Run AFTER 004_storage.sql
-- Safe to re-run: `on conflict ... do update` (not `do nothing`) so this
-- also repairs a bucket that already exists but with public=false (e.g.
-- one created by hand via the dashboard, which defaults to private).

-- ============================================================
-- BUCKET
-- reply-photos: public — photo attached to a reply, uploaded by
-- an anonymous (unauthenticated) recipient on the public /card/{id}
-- page using the anon key, not a signed-in sender.
-- ============================================================

insert into storage.buckets (id, name, public)
values ('reply-photos', 'reply-photos', true)
on conflict (id) do update set public = true;

-- ============================================================
-- STORAGE RLS
-- Unlike card-html/teaser-images (uploaded by authenticated
-- senders), reply photos are uploaded by anonymous recipients,
-- so the insert policy must grant `anon`, not `authenticated`.
-- ============================================================

-- reply-photos: anonymous upload
create policy "reply-photos: anon can upload"
  on storage.objects for insert
  to anon
  with check (bucket_id = 'reply-photos');

-- reply-photos: public read
create policy "reply-photos: public read"
  on storage.objects for select
  using (bucket_id = 'reply-photos');
