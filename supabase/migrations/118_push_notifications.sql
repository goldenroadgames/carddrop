-- Push notifications for replies and emoji reactions, plus the "opened"
-- eyeball. See carddrop/push_notifications_plan.md.
--
-- push_tokens: one row per device token. Written only by the
-- register-push-token and send-push code (service role); RLS on, no policies.
-- cards.first_opened_at: set once by the card-opened function when a recipient
-- really views the web page (flip / tap / scroll / 20 s visible). The sender
-- already reads their own cards ("cards: sender reads own"), so the app shows
-- the eyeball from this column. No push is sent for an open.
-- users.notify_replies: the single notifications switch (replies and
-- reactions), default on. Written through register-push-token.
create table if not exists push_tokens (
  id            bigint generated always as identity primary key,
  user_id       uuid not null,
  device_token  text not null unique,
  environment   text not null check (environment in ('sandbox', 'production')),
  updated_at    timestamptz not null default now()
);

create index if not exists push_tokens_user_idx on push_tokens (user_id);

alter table push_tokens enable row level security;
revoke all on push_tokens from anon, authenticated;

alter table cards add column if not exists first_opened_at timestamptz;
alter table users add column if not exists notify_replies boolean not null default true;
