-- CardDrop schema
-- Run in Supabase SQL editor (Database > SQL editor)

-- ============================================================
-- TABLES
-- ============================================================

create table users (
  id                uuid primary key default gen_random_uuid(),
  device_uuid       uuid unique not null,
  email             text unique,
  phone             text unique,
  apple_id          text unique,
  tier              text not null default 'free',  -- 'free' | 'unlimited'
  sends_this_month  int not null default 0,
  push_token        text,
  created_at        timestamptz not null default now()
);

create table cards (
  id                uuid primary key default gen_random_uuid(),
  sender_id         uuid not null references users(id),
  recipient_phone   text,
  recipient_email   text,
  recipient_name    text,
  message_preview   text,
  card_html_url     text not null,
  teaser_image_url  text not null,
  sent_at           timestamptz not null default now(),
  expires_at        timestamptz  -- null = permanent (unlimited tier)
);

create table reactions (
  id        uuid primary key default gen_random_uuid(),
  card_id   uuid not null references cards(id) on delete cascade,
  emoji     text not null,  -- '❤️'|'😂'|'😮'|'🥹'|'🙏'|'😜'
  sent_at   timestamptz not null default now()
);

create table replies (
  id               uuid primary key default gen_random_uuid(),
  card_id          uuid not null references cards(id) on delete cascade,
  reply_text       text,
  reply_image_url  text,
  sent_at          timestamptz not null default now(),
  viewed_at        timestamptz
);

create table card_views (
  id          uuid primary key default gen_random_uuid(),
  card_id     uuid not null references cards(id) on delete cascade,
  viewed_at   timestamptz not null default now(),
  user_agent  text
);

-- ============================================================
-- INDEXES
-- ============================================================

create index on cards(sender_id);
create index on cards(expires_at) where expires_at is not null;
create index on reactions(card_id);
create index on replies(card_id);
create index on card_views(card_id);
