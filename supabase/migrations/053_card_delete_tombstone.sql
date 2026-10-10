-- Card delete = tombstone. The `cards` row stays (deleted_at set by the
-- delete-card Edge Function, content columns blanked) so /card can show
-- "removed by its sender"; every file and child row is purged. See
-- carddrop/card_delete_complaints_bans_plan.md.

-- The function blanks teaser_image_url on delete; it was NOT NULL since 001.
alter table cards alter column teaser_image_url drop not null;

-- Set when every file and child row for a deleted card is gone. A tombstone
-- with deleted_at set and purged_at null means the purge failed partway; the
-- sweep-deleted-cards function retries those.
alter table cards add column if not exists purged_at timestamptz;

create index if not exists cards_unpurged_idx
  on cards (deleted_at)
  where deleted_at is not null and purged_at is null;

-- For browsing in the dashboard only. Not exposed to the apps.
create or replace view deleted_cards as
  select id, sender_id, sent_at, expires_at, deleted_at, purged_at
  from cards
  where deleted_at is not null;

alter view deleted_cards set (security_invoker = true);
revoke all on deleted_cards from anon, authenticated;
