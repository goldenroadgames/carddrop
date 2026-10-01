-- Adds a third promo discount type alongside percent/fixed (see
-- 025_promo_codes.sql): price_override forces the final price to a
-- specific value regardless of the size's current price (e.g. a flash-sale
-- "$0.99 postcards" code), rather than discounting off whatever the
-- current price happens to be.
--
-- discount_value's meaning now depends on discount_type: for percent/fixed
-- it's the amount taken off; for price_override it's the resulting price
-- itself, both in the same unit as before (cents for fixed/price_override,
-- whole percent for percent). The edge functions clamp the computed
-- discount so a price_override can never exceed the current price (i.e.
-- never make the customer pay MORE than the normal price).

alter table promo_codes drop constraint promo_codes_discount_type_check;
alter table promo_codes add constraint promo_codes_discount_type_check
  check (discount_type in ('percent', 'fixed', 'price_override'));
