-- Monthly per-user send stats: one row per user per month, kept for a rolling
-- window (user_send_stats_months in zz_config; the sweeper deletes older rows).
--   digital_sends  successful send-card calls
--   mail_orders    orders submitted to Lob (submit-to-lob)
--   rate_cap_hits  send-card calls refused by the hourly/daily send-rate cap
--                  (a count only; no times)
-- No foreign key, like send_events, so deleting a card or user never changes
-- a count here; account deletion removes the user's rows explicitly.
-- RLS on with no policies: only the service role (edge functions, admin pages)
-- can read or write it.

create table if not exists user_send_stats (
  user_id       uuid not null,
  month_key     text not null,                 -- 'YYYY-MM' (UTC)
  digital_sends int  not null default 0,
  mail_orders   int  not null default 0,
  rate_cap_hits int  not null default 0,
  updated_at    timestamptz not null default now(),
  primary key (user_id, month_key)
);

alter table user_send_stats enable row level security;

-- Atomic increment for the current month. p_field is one of the three
-- counter columns; anything else is ignored.
create or replace function bump_user_send_stat(p_user_id uuid, p_field text)
returns void
language plpgsql
set search_path = public
as $$
declare
  v_month text := to_char(now() at time zone 'utc', 'YYYY-MM');
begin
  if p_field not in ('digital_sends', 'mail_orders', 'rate_cap_hits') then
    return;
  end if;
  execute format(
    'insert into user_send_stats (user_id, month_key, %1$I) values ($1, $2, 1)
     on conflict (user_id, month_key)
     do update set %1$I = user_send_stats.%1$I + 1, updated_at = now()',
    p_field)
  using p_user_id, v_month;
end;
$$;

revoke all on function bump_user_send_stat(uuid, text) from public, anon, authenticated;
grant execute on function bump_user_send_stat(uuid, text) to service_role;

insert into zz_config (key, value, description) values
  ('user_send_stats_months', '13', 'Months of per-user monthly send stats kept before the sweeper deletes them')
on conflict (key) do nothing;
