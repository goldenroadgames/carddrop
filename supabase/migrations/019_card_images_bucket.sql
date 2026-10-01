-- New public storage bucket, replacing "teaser-images" (a misleading name —
-- that bucket actually held every public card image: front, back, back6x9,
-- and the composite thumbnail, not just an email/SMS "teaser"). Renamed to
-- "card-images" for accuracy. Nothing in "teaser-images" is worth migrating,
-- so this is a clean cutover — the old bucket is left in place, untouched,
-- for manual cleanup later.
-- Run AFTER 004_storage.sql

insert into storage.buckets (id, name, public)
values ('card-images', 'card-images', true)
on conflict (id) do nothing;

create policy "card-images: auth users can upload"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'card-images');

create policy "card-images: public read"
  on storage.objects for select
  using (bucket_id = 'card-images');
