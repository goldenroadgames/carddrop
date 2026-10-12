-- Housekeeping for suspended accounts that are never appealed or reinstated:
-- the sweeper deletes the account's data suspension_delete_days after the
-- suspension began (default 180), unless there is an open appeal or the ban is
-- on legal hold. Same deletion routine and same kept records as a final
-- suspension (which keeps its own, shorter rule: final_suspension_delete_days).
insert into zz_config (key, value, description) values
  ('suspension_delete_days', '180', 'Days after a suspension begins before an unappealed account''s data is deleted (open appeal or legal hold pauses it)')
on conflict (key) do nothing;
