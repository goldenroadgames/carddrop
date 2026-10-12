-- Reported-card review: a per-card audit log (views and admin actions) and a
-- recorded decision on each complaint. Run BEFORE deploying the web changes
-- and the updated submit-complaint.

-- Decision on the complaint row. The reporter's answers (involves_minor,
-- complaint_text) are never changed; the decision sits beside them.
--   dismissed       report reviewed and dismissed (card unhidden, strike cleared)
--   child_confirmed admin confirmed a child-safety concern (card held, account
--                   suspended as final and held); ncmec_report_id is typed in
--                   after the CyberTipline report is filed by hand
alter table card_complaints
  add column if not exists decision        text check (decision in ('dismissed', 'child_confirmed')),
  add column if not exists decided_at      timestamptz,
  add column if not exists decided_by      text,
  add column if not exists ncmec_report_id text,
  add column if not exists first_viewed_at timestamptz;   -- set when an admin first opens it; drives "unviewed first"

-- Append-only log. No FK on purpose: it must outlive the card and the account.
create table if not exists card_view_log (
  id          uuid primary key default gen_random_uuid(),
  card_id     uuid not null,
  sender_id   uuid,
  event       text not null check (event in ('view', 'dismissed', 'child_confirmed', 'suspended', 'hold', 'release')),
  reason      text,           -- why (e.g. 'report review')
  note        text,
  viewed_by   text,
  created_at  timestamptz not null default now()
);

create index if not exists card_view_log_card_idx on card_view_log (card_id, created_at);

alter table card_view_log enable row level security;   -- service role only
