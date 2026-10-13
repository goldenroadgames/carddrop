-- How long ended records are kept before the nightly sweep deletes them: the
-- review log on reported cards, report records, reinstated suspensions and
-- their resolved appeals. Anything still doing a job is kept regardless: an
-- active or final suspension, a legal hold, a CSAM review decision.
-- (retention_days, 365, still governs complaint text, the send log, block
-- records, order snapshots and reported cards.)
insert into zz_config (key, value, description) values
  ('history_retention_days', '730', 'Days the card review log, report records, reinstated suspensions and resolved appeals are kept (unless held or still suspended)')
on conflict (key) do nothing;
