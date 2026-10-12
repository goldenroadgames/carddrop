-- The reason an admin chose when reinstating a suspension (from an appeal or
-- from the Suspended page), kept on the suspension itself. Internal only.
alter table account_bans add column if not exists reinstated_reason text;
