-- "Delete data now" on the admin Suspended page (for example after an email
-- asking for deletion): marks the active suspension as deletion-requested; the
-- sweeper then deletes the account's data on its next run, whether or not the
-- suspension is final (a legal hold still wins). Same routine and kept records
-- as every other deletion. Clearing the column cancels the request.
alter table account_bans add column if not exists delete_requested_at timestamptz;
