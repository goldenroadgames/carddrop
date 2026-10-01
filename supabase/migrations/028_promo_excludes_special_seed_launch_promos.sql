-- Adds an "excludes special pricing" flag to promo_codes and seeds three
-- launch promos, one per discount_type (see 025_promo_codes.sql and
-- 027_promo_price_override.sql).
--
-- "Special" vs. "regular" price is NOT a new concept/column on
-- postcard_pricing — it falls out of the existing SCD2 shape (024):
-- postcard_pricing_one_current_per_size guarantees at most one open-ended
-- (effective_to is null) row per size, which is the standing "regular"
-- price. Whenever postcard_current_pricing's winning row for a size has a
-- non-null effective_to, that means a narrower, temporary window beat out
-- the open-ended row — i.e. a "special" price is currently in effect. So a
-- promo that should skip specials just needs to know whether the resolved
-- price row's effective_to is null, no join back to postcard_pricing's
-- description text needed. validate-promo-code enforces this.

alter table promo_codes
  add column excludes_special_pricing boolean not null default false;

-- twobucks: force the final price to $2.00, 4x6 only. A price_override
-- applies even during a special, since the whole point is a flat flash
-- price regardless of what's currently charged.
insert into promo_codes (code, discount_type, discount_value, applicable_sizes, excludes_special_pricing)
values ('twobucks', 'price_override', 200, array['4x6'], false);

-- oneoff: $1.00 off, both sizes, regular pricing only.
insert into promo_codes (code, discount_type, discount_value, applicable_sizes, excludes_special_pricing)
values ('oneoff', 'fixed', 100, array['4x6', '6x9'], true);

-- save20: 20% off, both sizes, regular pricing only.
insert into promo_codes (code, discount_type, discount_value, applicable_sizes, excludes_special_pricing)
values ('save20', 'percent', 20, array['4x6', '6x9'], true);
