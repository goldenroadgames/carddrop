-- One retention setting for the "kept 12 months" data: complaint text, order
-- name/address snapshots, the digital send log, moderation block records, and
-- reported cards kept as evidence (sweep-deleted-cards). Terms, Privacy and the
-- report page say "about {{retention_days}} days", filled from this row.
insert into zz_config (key, value, description) values
  ('retention_days', '365', 'Days complaint text, send log, order snapshots, block records and reported cards are kept before the sweeper deletes them')
on conflict (key) do nothing;
