-- Suspension appeals through a form in the app (submit-appeal Edge Function),
-- reviewed on /grg_admin/appeals. Uses the existing ban_reviews table (006),
-- which nothing used before.
--
-- 1. content_blocks.scores: the highest OpenAI score per flagged category, so
--    an appeal review can tell a borderline flag from a clear one.
-- 2. ban_reviews.outcome ('reinstated' | 'denied'); `resolution` holds the
--    note shown to the user, `resolved_at` is when it was decided.
-- 3. One open appeal per user.
-- 4. Clients can no longer write ban_reviews at all (the old "insert own"
--    policy let a client set the decision fields on its own row). The function
--    inserts with the service role; the "read own" policy stays so the app
--    can show the status.
alter table content_blocks add column if not exists scores jsonb not null default '{}'::jsonb;

alter table ban_reviews add column if not exists outcome text
  check (outcome in ('reinstated', 'denied'));

create unique index if not exists ban_reviews_one_open_per_user
  on ban_reviews (user_id) where resolved_at is null;

drop policy if exists "ban_reviews: insert own" on ban_reviews;
revoke insert, update, delete, truncate on ban_reviews from anon, authenticated;

-- Appeals stop being offered once an account has been reinstated this many
-- times (2 = the third suspension is final; 1 = the second is final).
insert into zz_config (key, value, description) values
  ('appeal_max_reinstatements', '2', 'Suspensions after this many earlier reinstatements are final: no appeal form')
on conflict (key) do nothing;
