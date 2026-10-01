-- Drops two retired storage buckets entirely (policies + objects + the
-- bucket row itself) — no dashboard steps needed, this migration alone is
-- sufficient. Deleting rows from storage.objects/storage.buckets is
-- irreversible; both were confirmed unused/expendable before writing this.

-- card-html: a standalone animated flip-card HTML file, uploaded and served
-- per card — superseded by the webapp's /card/[id] page (CardView.tsx)
-- rendering/flipping natively. Confirmed: no Swift/TS/Edge Function code
-- path references it, and it holds no objects worth keeping.
drop policy if exists "card-html: auth users can upload" on storage.objects;
drop policy if exists "card-html: public read" on storage.objects;
delete from storage.objects where bucket_id = 'card-html';
delete from storage.buckets where id = 'card-html';

-- teaser-images: replaced by "card-images" (019_card_images_bucket.sql) —
-- the misleadingly-named original bucket that actually held every public
-- card image (front/back/back6x9/composite), not just an email/SMS teaser.
-- Nothing in it is worth keeping.
drop policy if exists "teaser-images: auth users can upload" on storage.objects;
drop policy if exists "teaser-images: public read" on storage.objects;
delete from storage.objects where bucket_id = 'teaser-images';
delete from storage.buckets where id = 'teaser-images';
