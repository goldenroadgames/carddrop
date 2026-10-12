-- Reasons for dismissing a reported card (dropdown on the opened-card page),
-- kept in the same decision_reasons table you already edit in the Supabase
-- table viewer. 'dismissed' rows appear ONLY in that dropdown. Run after 093.
alter table decision_reasons drop constraint if exists decision_reasons_applies_to_check;
alter table decision_reasons
  add constraint decision_reasons_applies_to_check
  check (applies_to in ('reinstated', 'denied', 'both', 'dismissed'));

insert into decision_reasons (label, applies_to, sort_order) values
  ('Card does not violate our terms',        'dismissed', 310),
  ('No child shown',                         'dismissed', 320),
  ('Duplicate or mistaken report',           'dismissed', 330),
  ('Flagged by admin in error',              'dismissed', 340),
  ('Other',                                  'dismissed', 900)
on conflict (label) do nothing;

-- Which reason was chosen. For a "CSAM review required" decision it is the
-- fixed text 'CSAM review required'.
alter table card_complaints add column if not exists decision_reason text;
