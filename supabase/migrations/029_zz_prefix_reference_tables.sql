-- Prefixes the app's reference/settings tables (standing config + catalog
-- data, as opposed to transactional/user-generated rows) with zz_ so they
-- sort to the bottom of the table list, away from the transactional tables
-- (cards, card_recipients, physical_orders, promo_code_redemptions, etc.).
-- Renaming only the table/view names themselves — indexes, constraints, and
-- RLS policy labels keep their existing names; a table rename doesn't
-- require renaming those for anything to keep working.

alter table cardback_greetings rename to zz_cardback_greetings;
alter table cardback_phrases rename to zz_cardback_phrases;
alter table config rename to zz_config;
alter table postcard_products rename to zz_postcard_products;
alter table postcard_pricing rename to zz_postcard_pricing;

-- A table rename updates any view built on top of it automatically (views
-- reference dependencies by OID, not by name) — only the view's own name
-- needs renaming here.
alter view postcard_current_pricing rename to zz_postcard_current_pricing;

alter table promo_codes rename to zz_promo_codes;
