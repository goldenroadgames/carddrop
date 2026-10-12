-- Server-written log of send-card calls, used by the send-rate cap
-- (send_rate_hourly / send_rate_daily in zz_config, added in 086).
-- Counting cards.sent_at missed resends (same card row), and card_recipients
-- is written by the app and cascades away when a card is deleted. This table
-- has no foreign key to cards, so deleting a card never resets the count.
-- RLS on with no policies: only the service role (edge functions) can read
-- or write it.

create table if not exists send_events (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null,
  card_id    uuid,
  created_at timestamptz not null default now()
);

alter table send_events enable row level security;

create index if not exists send_events_user_created_idx
  on send_events (user_id, created_at desc);

-- 086's index on cards is no longer used by the cap.
drop index if exists cards_sender_sent_at_idx;
