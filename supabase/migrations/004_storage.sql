-- CardDrop storage bucket setup
-- Run AFTER 001_schema.sql and 002_rls.sql
-- Safe to re-run (on conflict do nothing)

-- ============================================================
-- BUCKETS
-- card-html:     public — the self-contained animated HTML file
-- teaser-images: public — preview image sent with email/text
-- ============================================================

insert into storage.buckets (id, name, public)
values ('card-html', 'card-html', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('teaser-images', 'teaser-images', true)
on conflict (id) do nothing;

-- ============================================================
-- STORAGE RLS
-- Authenticated senders can upload their own card files.
-- Public can read all files in both buckets (bucket is public,
-- but explicit select policies are belt-and-suspenders).
-- ============================================================

-- card-html: authenticated upload
create policy "card-html: auth users can upload"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'card-html');

-- card-html: public read
create policy "card-html: public read"
  on storage.objects for select
  using (bucket_id = 'card-html');

-- teaser-images: authenticated upload
create policy "teaser-images: auth users can upload"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'teaser-images');

-- teaser-images: public read
create policy "teaser-images: public read"
  on storage.objects for select
  using (bucket_id = 'teaser-images');
