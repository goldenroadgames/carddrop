-- CardDrop RLS policies
-- Run AFTER 001_schema.sql

-- ============================================================
-- Enable RLS on all tables
-- ============================================================

alter table users enable row level security;
alter table cards enable row level security;
alter table reactions enable row level security;
alter table replies enable row level security;
alter table card_views enable row level security;

-- ============================================================
-- users
-- ============================================================

-- Read own record
create policy "users: read own"
  on users for select
  using (auth.uid() = id);

-- Insert own record (on first launch)
create policy "users: insert own"
  on users for insert
  with check (auth.uid() = id);

-- Update own record (push token, tier, etc.)
create policy "users: update own"
  on users for update
  using (auth.uid() = id);

-- ============================================================
-- cards
-- ============================================================

-- Sender reads own cards
create policy "cards: sender reads own"
  on cards for select
  using (auth.uid() = sender_id);

-- Anyone reads any card by ID (recipient needs no account)
create policy "cards: public read by id"
  on cards for select
  using (true);

-- Authenticated users insert own cards
create policy "cards: insert own"
  on cards for insert
  with check (auth.uid() = sender_id);

-- ============================================================
-- reactions
-- ============================================================

-- Anyone inserts (recipient has no account)
create policy "reactions: anyone inserts"
  on reactions for insert
  with check (true);

-- Sender reads reactions on own cards
create policy "reactions: sender reads own card reactions"
  on reactions for select
  using (
    exists (
      select 1 from cards
      where cards.id = reactions.card_id
        and cards.sender_id = auth.uid()
    )
  );

-- ============================================================
-- replies
-- ============================================================

-- Anyone inserts (recipient has no account)
create policy "replies: anyone inserts"
  on replies for insert
  with check (true);

-- Sender reads replies on own cards
create policy "replies: sender reads own card replies"
  on replies for select
  using (
    exists (
      select 1 from cards
      where cards.id = replies.card_id
        and cards.sender_id = auth.uid()
    )
  );

-- Sender updates viewed_at on own cards' replies
create policy "replies: sender updates viewed_at"
  on replies for update
  using (
    exists (
      select 1 from cards
      where cards.id = replies.card_id
        and cards.sender_id = auth.uid()
    )
  );

-- ============================================================
-- card_views
-- ============================================================

-- Anyone inserts (anonymous analytics)
create policy "card_views: anyone inserts"
  on card_views for insert
  with check (true);

-- No reads via RLS (service role only)
-- No select policy = nobody can read via client
