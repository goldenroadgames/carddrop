-- Promo codes: a redeemable discount rule, structurally separate from
-- postcard_pricing (a base price) — different shape (code, discount,
-- redemption limits vs. a size/amount/date range) and different query
-- pattern (validate-a-code vs. look-up-current-price).
--
-- Redemption limits (max_redemptions, per_user_limit) are enforced by the
-- edge function reading promo_code_redemptions, NOT by a DB constraint —
-- keeps the limit logic (which needs "how many rows exist for this
-- code/user so far") in one place rather than split between a trigger and
-- application code.

create table promo_codes (
  id                uuid primary key default gen_random_uuid(),
  code              text not null,
  discount_type     text not null check (discount_type in ('percent', 'fixed')),
  -- percent: 1-100 (whole percent off). fixed: cents off, must be >= 1.
  -- Which bound applies is enforced together with discount_type below.
  discount_value    integer not null check (discount_value > 0),
  -- null = applies to every size. Otherwise e.g. '{4x6}' or '{4x6,6x9}'.
  applicable_sizes  text[],
  max_redemptions   integer check (max_redemptions is null or max_redemptions > 0),
  per_user_limit    integer check (per_user_limit is null or per_user_limit > 0),
  starts_at         timestamptz,
  expires_at        timestamptz,
  is_active         boolean not null default true,
  created_at        timestamptz not null default now(),

  constraint promo_codes_valid_window check (starts_at is null or expires_at is null or expires_at > starts_at),
  constraint promo_codes_percent_range check (
    discount_type <> 'percent' or discount_value <= 100
  ),
  constraint promo_codes_applicable_sizes_valid check (
    applicable_sizes is null or applicable_sizes <@ array['4x6', '6x9']
  )
);

-- Codes are looked up case-insensitively; this also guarantees no two rows
-- collide once the app normalizes to uppercase on entry.
create unique index promo_codes_code_unique on promo_codes(upper(code));

alter table promo_codes enable row level security;

-- No client select policy at all: codes are validated server-side only, via
-- an edge function using the service role key (so a client can't enumerate
-- valid codes, discount amounts, or remaining redemption counts by reading
-- the table directly — it can only submit a code string and get back
-- "valid, here's the discount" or "invalid").

-- One row per successful redemption — inserted by the edge function only
-- once an order reaches 'paid' status, NOT at code-entry/validation time, so
-- an abandoned checkout never consumes a limited code's redemption slot.
create table promo_code_redemptions (
  id             uuid primary key default gen_random_uuid(),
  promo_code_id  uuid not null references promo_codes(id),
  user_id        uuid not null references auth.users(id),
  order_id       uuid not null references physical_orders(id) on delete cascade,
  discount_cents integer not null check (discount_cents >= 0),
  redeemed_at    timestamptz not null default now(),

  -- A promo can only be applied once per order.
  constraint promo_code_redemptions_one_per_order unique (order_id)
);

create index on promo_code_redemptions(promo_code_id);
create index on promo_code_redemptions(user_id);

alter table promo_code_redemptions enable row level security;

-- User reads their own redemption history. No insert/update/delete policy —
-- written only by the edge function via the service role key.
create policy "promo_code_redemptions: user reads own"
  on promo_code_redemptions for select
  using (auth.uid() = user_id);

-- Snapshot of whichever promo (if any) was applied to this order, so the
-- discount stays accurate even if the promo_codes row later changes/expires
-- — same snapshot principle as physical_orders' address/amount columns.
alter table physical_orders
  add column promo_code_id  uuid references promo_codes(id),
  add column discount_cents integer not null default 0 check (discount_cents >= 0);
