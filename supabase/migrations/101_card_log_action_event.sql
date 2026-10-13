-- "Record an action": a dated entry you add by hand to a card's (or an
-- account's) log, for example "NCMEC report filed" or "Law enforcement
-- contacted", with a one-line note. Stored in card_view_log as event 'action':
-- reason = the action type, note = your line. Entries for NCMEC and law
-- enforcement are never swept (see sweepHistory). Account-level entries use the
-- all-zero card id and the account's id in sender_id.
alter table card_view_log drop constraint if exists card_view_log_event_check;
alter table card_view_log
  add constraint card_view_log_event_check
  check (event in ('view', 'dismissed', 'child_confirmed', 'suspended', 'hold', 'release', 'unlock', 'unlock_failed', 'action'));
