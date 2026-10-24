-- Repeat reports on an already-reported card add no strike, but the review
-- pages should show how many came in and when the latest was.
-- report_count starts at 1 (the first report); last_reported_at starts at
-- created_at. submit-complaint calls bump_complaint_report on every repeat.
alter table card_complaints add column if not exists report_count integer not null default 1;
alter table card_complaints add column if not exists last_reported_at timestamptz;
update card_complaints set last_reported_at = created_at where last_reported_at is null;
alter table card_complaints alter column last_reported_at set default now();
alter table card_complaints alter column last_reported_at set not null;

create or replace function bump_complaint_report(p_card_id uuid)
returns void
language sql
as $$
  update card_complaints
     set report_count = report_count + 1,
         last_reported_at = now()
   where card_id = p_card_id;
$$;

revoke all on function bump_complaint_report(uuid) from public, anon, authenticated;
grant execute on function bump_complaint_report(uuid) to service_role;
