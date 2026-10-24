-- Per-IP rate limit for the public report form (submit-complaint). Every
-- attempt stores only a keyed hash of the visitor's IP address and a
-- timestamp: no card, no sender. Service role only (RLS on, no policies, no
-- grants). The limit looks back one hour; the nightly sweeper deletes rows
-- older than 2 days.
create table if not exists report_attempts (
  id          bigint generated always as identity primary key,
  ip_hash     text not null,
  created_at  timestamptz not null default now()
);

create index if not exists report_attempts_ip_time_idx
  on report_attempts (ip_hash, created_at desc);

alter table report_attempts enable row level security;
revoke all on report_attempts from anon, authenticated;

-- Tunable without a deploy. Reports allowed per IP per rolling hour.
insert into zz_config (key, value, description) values
  ('report_attempts_per_ip_hourly', '3', 'Max card reports per IP address per hour on the public report form')
on conflict (key) do nothing;
