-- Backs the "Add to Carousel" checkbox on the admin "Manage Marketing
-- Photos" tool — flags a marketing_cards row for inclusion in the public
-- landing-page carousel (see project_landing_carousel_pile memory).
alter table marketing_cards add column if not exists in_carousel boolean not null default false;
