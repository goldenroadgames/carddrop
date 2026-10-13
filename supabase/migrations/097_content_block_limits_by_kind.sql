-- Separate strike tiers for blocked photos and blocked text (see
-- _shared/contentBlocks.ts). Every blocked item now counts, whatever the
-- category. Each kind has its own 24-hour and 30-day limit; reaching any one
-- suspends the account and device. Seeded at photos 4 / 10 and text 10 / 30
-- (adjust in zz_config). The old shared keys are only a
-- fallback and can be deleted once these are set.
insert into zz_config (key, value, description) values
  ('content_block_limit_photo_24h', '4',  'Counted blocked photos in 24 hours that suspend an account'),
  ('content_block_limit_photo_30d', '10', 'Counted blocked photos in 30 days that suspend an account'),
  ('content_block_limit_text_24h',  '10', 'Counted blocked text items in 24 hours that suspend an account'),
  ('content_block_limit_text_30d',  '30', 'Counted blocked text items in 30 days that suspend an account')
on conflict (key) do nothing;
