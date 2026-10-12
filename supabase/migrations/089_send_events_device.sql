-- The send-rate cap (send_rate_hourly / send_rate_daily) now also applies per
-- device, using the same limits. device_uuid is supplied by the app, so this
-- is a backstop against one phone making many accounts.
alter table send_events add column if not exists device_uuid text;

create index if not exists send_events_device_created_idx
  on send_events (device_uuid, created_at desc);

-- Separate device caps, so they can be changed independently of the account
-- caps. Same values to start with (the function also falls back to the
-- account caps if these rows are missing).
insert into zz_config (key, value, description) values
  ('send_rate_device_hourly', '10', 'Max cards one device can send in a rolling hour, across all accounts (-1 = no cap)'),
  ('send_rate_device_daily',  '50', 'Max cards one device can send in a rolling 24 hours, across all accounts (-1 = no cap)')
on conflict (key) do nothing;
