-- Held cards' images are private (reported or on legal hold) and are shown in
-- the admin pages only after a second password. Each unlock and each failed
-- attempt is written to the card log. They belong to no single card, so they use
-- the all-zero card id.
alter table card_view_log drop constraint if exists card_view_log_event_check;
alter table card_view_log
  add constraint card_view_log_event_check
  check (event in ('view', 'dismissed', 'child_confirmed', 'suspended', 'hold', 'release', 'unlock', 'unlock_failed'));
