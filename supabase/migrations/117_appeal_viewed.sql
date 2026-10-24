-- Admin Appeals page: an appeal counts as reviewed the first time a staff
-- member expands it, even if no decision is taken. Opening does NOT stop the
-- sweeper's auto-close (appeal_auto_deny_days); it is a record and an
-- "unread" dot only. Written by the web admin (service role).
alter table ban_reviews add column if not exists first_viewed_at timestamptz;
alter table ban_reviews add column if not exists viewed_by text;
