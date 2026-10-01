-- Standing catalog entry per postcard size — NOT versioned/effective-dated,
-- unlike postcard_pricing below. Holds the size's permanent tagline (e.g.
-- "Standard size, vintage chic") so it doesn't need to be re-copied into
-- every new postcard_pricing row whenever the price changes.
create table postcard_products (
  size                text primary key check (size in ('4x6', '6x9')),
  product_description text not null default '',
  updated_at          timestamptz not null default now()
);

alter table postcard_products enable row level security;

create policy "postcard_products: anyone reads"
  on postcard_products for select
  using (true);

-- Base price per physical postcard size, effective-dated so past prices
-- stay queryable even after a change (an SCD2-style history table, not just
-- a "current price" row). "Current" for a size is the row with
-- effective_to is null; changing a price means closing out the open row
-- (setting its effective_to) and inserting a new open row, never editing an
-- existing row's amount_cents in place.
--
-- This is the ONLY source of truth for postcard pricing — no Stripe
-- Product/Price catalog is used. The create-postcard-payment-intent edge
-- function (not yet built) reads the current row for the chosen size
-- server-side and passes that amount directly to Stripe's PaymentIntents
-- API as a raw `amount`, so the client can never influence what's charged.

create table postcard_pricing (
  id                            uuid primary key default gen_random_uuid(),
  size                          text not null check (size in ('4x6', '6x9')),
  amount_cents                  integer not null check (amount_cents >= 0),
  currency                      text not null default 'usd',
  -- Size-picker copy for THIS priced period specifically. Both optional —
  -- null falls back to postcard_products.product_description; set either
  -- one here to override just for as long as this price row is current
  -- (e.g. a seasonal re-worded tagline, or a launch-special call-out) without
  -- touching the standing catalog entry.
  product_description_override text,
  special_description           text,
  effective_from                timestamptz not null default now(),
  effective_to                  timestamptz,
  created_at                    timestamptz not null default now(),

  constraint postcard_pricing_valid_range check (effective_to is null or effective_to > effective_from)
);

-- At most one open (current) price per size.
create unique index postcard_pricing_one_current_per_size
  on postcard_pricing(size)
  where effective_to is null;

create index on postcard_pricing(size, effective_from);

alter table postcard_pricing enable row level security;

-- Any authenticated (or anonymous) user can read pricing — it's needed to
-- render the size picker before checkout. No insert/update/delete policy:
-- pricing changes are an admin/operator action, done via the SQL editor or
-- an edge function using the service role key, never directly by the client.
create policy "postcard_pricing: anyone reads"
  on postcard_pricing for select
  using (true);

-- Resolves "the current price" per size when more than one row's window
-- contains right now — e.g. a standing open-ended price plus a short-term
-- special that overlaps it. Rule: among rows where now() falls within
-- [effective_from, effective_to), the row with the SOONEST effective_to
-- wins (an open-ended/null effective_to sorts last, i.e. loses to any
-- row with a real end date) — the more specific/narrower-window row takes
-- priority over the standing one. Ties (identical effective_to) break on
-- the most recently created row. This view, not the raw table, is what the
-- create-postcard-payment-intent edge function and the size-picker UI
-- should actually query.
create view postcard_current_pricing as
select distinct on (size) *
from postcard_pricing
where effective_from <= now()
  and (effective_to is null or effective_to > now())
order by size, effective_to asc nulls last, created_at desc;
