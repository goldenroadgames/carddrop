-- Separate from in_carousel (038) — the landing-page carousel and the
-- in-app "Get Inspired" gallery are two different destinations, curated
-- independently (a card can be right for one without being right for the
-- other). Backs the new "Add to Inspire" checkbox on the admin "Manage
-- Marketing Photos" tool.
alter table marketing_cards add column if not exists in_inspire boolean not null default false;
