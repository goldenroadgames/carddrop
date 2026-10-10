-- Monthly free-postcard allowances for specific accounts (friends & family).
--
-- zz_account_allowances holds only the LIMIT. There is no usage counter and
-- nothing to reset: usage is counted at checkout from physical_orders rows
-- where funded_by_allowance is true, created in the current calendar month
-- (UTC), and not 'failed' / 'refunded'. On the 1st the count is zero again;
-- unused cards do not carry over. Whether an order ever reached LOB is
-- deliberately not checked (a stuck 'authorized' order still counts).
--
-- Hard cap of 5 per month enforced by the check constraint, so even a bad
-- insert can't exceed it. To grant (run in the SQL editor, 1-2 typical):
--   insert into zz_account_allowances (user_id, free_postcards_per_month, note)
--   values ('<auth user id>', 2, 'Mom');
-- To change or revoke: update the number / delete the row.
--
-- Server-only like zz_promo_codes: RLS on with no policies, so clients can
-- never read or write it; edge functions use the service role key.

create table zz_account_allowances (
  user_id                  uuid primary key references auth.users(id) on delete cascade,
  free_postcards_per_month integer not null
    check (free_postcards_per_month between 1 and 5),
  note                     text,
  created_at               timestamptz not null default now()
);

alter table zz_account_allowances enable row level security;

alter table physical_orders
  add column funded_by_allowance boolean not null default false;

create index physical_orders_allowance_usage_idx
  on physical_orders (sender_id, created_at)
  where funded_by_allowance;
