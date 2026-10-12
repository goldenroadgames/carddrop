-- Per-sender send-rate cap, enforced in send-card for every tier: cards per
-- rolling hour and per rolling day (-1 = no cap). Counted from cards.sent_at.
insert into zz_config (key, value, description) values
  ('send_rate_hourly', '10', 'Max cards a sender can send in a rolling hour (-1 = no cap)'),
  ('send_rate_daily',  '50', 'Max cards a sender can send in a rolling 24 hours (-1 = no cap)')
on conflict (key) do nothing;

create index if not exists cards_sender_sent_at_idx on cards (sender_id, sent_at desc);
