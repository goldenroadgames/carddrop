-- Per-IP rate limit for the new submit-reply edge function (web replies are
-- moderated and inserted server-side). Every attempt, accepted or rejected,
-- stores only a keyed hash of the visitor's IP address and a timestamp: no
-- card, no content. Service role only (RLS on, no policies, no grants).
-- The function deletes rows older than 2 days from time to time.
create table if not exists reply_attempts (
  id          bigint generated always as identity primary key,
  ip_hash     text not null,
  created_at  timestamptz not null default now()
);

create index if not exists reply_attempts_ip_time_idx
  on reply_attempts (ip_hash, created_at desc);

alter table reply_attempts enable row level security;
revoke all on reply_attempts from anon, authenticated;

-- Tunable without a deploy. Replies attempts allowed per IP per rolling hour.
insert into zz_config (key, value, description) values
  ('reply_attempts_per_ip_hourly', '10', 'Max web reply attempts (accepted or rejected) per IP address per hour')
on conflict (key) do nothing;
