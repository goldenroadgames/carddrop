-- An admin can make one suspension final by hand ("Deny & make final" on an
-- appeal, or "Make final" on the Suspended page), without waiting for the
-- reinstatement count. A final suspension has no appeal form and its account
-- data is deleted automatically final_suspension_delete_days after it began
-- (unless on legal hold), exactly like one that became final by count (077).
alter table account_bans add column if not exists final boolean not null default false;

-- Appeals nobody reviewed are closed automatically by the sweeper after this
-- many days (0 = never): recorded as denied, with a note saying it wasn't
-- reviewed in time, so the usual 30-day wait before another appeal applies.
insert into zz_config (key, value, description) values
  ('appeal_auto_deny_days', '30', 'Days an appeal can stay unreviewed before the sweeper closes it as denied (0 = never)')
on conflict (key) do nothing;

-- ban_reviews.resolution is now an INTERNAL note (the admin's reasoning, never
-- shown to the user). auto_closed marks an appeal the sweeper closed unreviewed:
-- the app tells the user it wasn't reviewed in time (a fixed message).
alter table ban_reviews add column if not exists auto_closed boolean not null default false;

-- Clients may read their own appeal rows (RLS "read own") but NOT the internal
-- `resolution` note: column-level grant instead of the table-wide SELECT.
revoke select on ban_reviews from anon, authenticated;
grant select (id, user_id, device_uuid, message, created_at, resolved_at, outcome, auto_closed)
  on ban_reviews to authenticated;
