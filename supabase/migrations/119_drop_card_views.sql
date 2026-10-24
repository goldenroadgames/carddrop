-- card_views recorded every web page view (card id, time, browser type) from the
-- public card page, but nothing ever read it. "Opened" is now cards.first_opened_at
-- (set by card-opened) and link expiry is extended by extend-card-link. Dropping the
-- table also removes its anonymous-insert policy.
-- RUN AFTER the web change (the card page no longer inserts) and after redeploying
-- functions, because purgeCard.ts no longer deletes from this table.
drop table if exists card_views;
