-- Seed data for zz_postcard_products + zz_postcard_pricing (migrations
-- 024/025, renamed to the zz_ prefix in 029).
-- Not run automatically — paste into the Supabase SQL editor and adjust the
-- prices/copy below before running. Safe to re-run: uses upsert-style
-- ON CONFLICT for zz_postcard_products, and only inserts a new
-- zz_postcard_pricing row if that size doesn't already have an open
-- (current) one.

insert into zz_postcard_products (size, product_description) values
  ('4x6', 'Standard size, vintage chic'),
  ('6x9', 'Go Big and Mail Home - more than twice the size of standard card')
on conflict (size) do update set
  product_description = excluded.product_description,
  updated_at = now();

insert into zz_postcard_pricing (size, amount_cents, currency, special_description)
select '4x6', 299, 'usd', null
where not exists (
  select 1 from zz_postcard_pricing where size = '4x6' and effective_to is null
);

insert into zz_postcard_pricing (size, amount_cents, currency, special_description)
select '6x9', 299, 'usd', 'Launch special - same price as standard'
where not exists (
  select 1 from zz_postcard_pricing where size = '6x9' and effective_to is null
);
