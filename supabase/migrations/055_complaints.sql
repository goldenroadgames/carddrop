-- Step 3 of carddrop/card_delete_complaints_bans_plan.md: recipient complaints,
-- mail blocks, strike counting, in-app notices. Run AFTER 054.

-- ------------------------------------------------------------------
-- 1. Complaints. One row per complained-about card (card_id unique =
--    "distinct cards"). No FKs on purpose: a complaint/strike must survive
--    the sender deleting the card or their account.
-- ------------------------------------------------------------------
create table if not exists card_complaints (
  id              uuid primary key default gen_random_uuid(),
  card_id         uuid not null unique,
  sender_id       uuid,
  device_uuid     uuid,
  complaint_text  text,
  block_all       boolean not null default false,
  created_at      timestamptz not null default now()
);

create index if not exists card_complaints_sender_idx on card_complaints (sender_id, created_at);
create index if not exists card_complaints_device_idx on card_complaints (device_uuid, created_at);

alter table card_complaints enable row level security;   -- service role only

-- ------------------------------------------------------------------
-- 2. Mail blocks. address_hash = sha256 of a normalized "street|zip5" (see
--    _shared/addressKey.ts), never the address itself. sender_id null = all
--    senders. Permanent.
-- ------------------------------------------------------------------
create table if not exists mail_blocks (
  id            uuid primary key default gen_random_uuid(),
  sender_id     uuid,
  address_hash  text not null,
  created_at    timestamptz not null default now()
);

create unique index if not exists mail_blocks_unique_idx
  on mail_blocks (coalesce(sender_id, '00000000-0000-0000-0000-000000000000'::uuid), address_hash);
create index if not exists mail_blocks_hash_idx on mail_blocks (address_hash);

alter table mail_blocks enable row level security;   -- service role only

-- ------------------------------------------------------------------
-- 3. In-app notices (complaint warnings, ban notices). The app reads its
--    own unseen notices at launch and marks them seen.
-- ------------------------------------------------------------------
create table if not exists user_notices (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null,
  kind        text not null check (kind in ('warning', 'ban')),
  message     text not null,
  created_at  timestamptz not null default now(),
  seen_at     timestamptz
);

create index if not exists user_notices_user_idx on user_notices (user_id) where seen_at is null;

alter table user_notices enable row level security;

create policy "user_notices: read own"
  on user_notices for select
  using (auth.uid() = user_id);

create policy "user_notices: mark own seen"
  on user_notices for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ------------------------------------------------------------------
-- 4. Order snapshot scrubbing marker (the sweeper nulls the recipient and
--    sender name/address columns 12 months after the order).
-- ------------------------------------------------------------------
alter table physical_orders add column if not exists scrubbed_at timestamptz;

-- ------------------------------------------------------------------
-- 5. Tunables
-- ------------------------------------------------------------------
insert into zz_config (key, value, description) values
  ('complaint_strikes_to_ban', '3',   'Distinct complained-about cards (by account or by device) within the window that trigger an automatic ban'),
  ('complaint_window_days',    '180', 'How far back complaints count toward a ban')
on conflict (key) do nothing;
