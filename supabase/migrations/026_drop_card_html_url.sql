-- card_html_url (cards, added in 001_schema.sql) pointed at a standalone
-- animated flip-card HTML file, served from the card-html storage bucket.
-- That format was superseded by the webapp's /card/[id] page, and the
-- card-html bucket itself was dropped in 020_drop_retired_buckets.sql — but
-- this column was apparently dropped from the live database manually at
-- some point afterward, outside of any committed migration, so the schema
-- had drifted from what this repo's migration history claimed. This
-- migration just formally codifies that removal so the two stay in sync
-- going forward — see supabase/functions/create-postcard-payment-intent,
-- whose `cards` upsert had to work around this drift already existing live.

alter table cards drop column if exists card_html_url;
