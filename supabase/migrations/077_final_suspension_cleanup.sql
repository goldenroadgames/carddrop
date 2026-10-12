-- Final suspensions: the sweeper deletes the account's data
-- final_suspension_delete_days after the suspension began (default 30), unless
-- the ban is on legal hold. A suspension is "final" when the account has
-- already been reinstated appeal_max_reinstatements times (see 076), counted
-- by account and by verified email. The ban record, device bans,
-- blocked-content records, reported-card evidence and order records are kept
-- (same rules as the app's Delete Account).
--
-- legal_hold: set from the admin Suspended page to stop the automatic deletion
-- (for example when something must be preserved). purged_at: when the sweeper
-- deleted the account's data, so it is not repeated.
alter table account_bans add column if not exists legal_hold boolean not null default false;
alter table account_bans add column if not exists purged_at timestamptz;

insert into zz_config (key, value, description) values
  ('final_suspension_delete_days', '30', 'Days after a final suspension begins before the account data is deleted automatically (unless on legal hold)')
on conflict (key) do nothing;
