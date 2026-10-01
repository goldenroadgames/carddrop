-- A single flowing, promotional-style sentence describing a card's front
-- design (filter, border, overlays, banner, QR) — built client-side from
-- style choices only, NEVER from user-entered text (message, greeting word,
-- names, addresses). Safe to be publicly readable (cards has a public
-- select-by-id policy) and safe to carry into marketing_cards unchanged
-- whenever that table/copy step is built.
alter table cards add column if not exists design_features text;

-- Small (max 600pt long edge, ~0.6 quality) JPEG of the front image,
-- uploaded to card-images/{sender_id}/{card_id}_thumb.jpg alongside the
-- full-resolution front/back images — for fast-loading admin/moderation
-- lists later, not for the public /card/[id] display (which keeps using
-- teaser_image_url).
alter table cards add column if not exists thumbnail_url text;
