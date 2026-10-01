-- Two additions to promo codes (see 025_promo_codes.sql, 029_zz_prefix_reference_tables.sql):
--
-- 1. is_free: the code makes the order cost $0. The edge functions then skip
--    Stripe entirely (no PaymentIntent) and the order is created already
--    'authorized'. Without this flag every discount is clamped to leave at
--    least Stripe's 50-cent minimum charge. Free is a deliberate setting,
--    never inferred from a large discount_value. Always pair it with a low
--    max_redemptions: every free card costs real LOB printing + postage.
--
-- 2. restricted + zz_promo_code_allowed_users: when restricted is true, only
--    the accounts listed in zz_promo_code_allowed_users can use the code.
--    An explicit flag (rather than "has rows") so a restricted code whose
--    allow-list rows get deleted never silently becomes open to everyone.
--    Sits on top of max_redemptions / per_user_limit, which still apply.
--    A caller not on the list gets the same "not_found" as a nonexistent
--    code, so a restricted code's existence can't be probed.

alter table zz_promo_codes
  add column is_free    boolean not null default false,
  add column restricted boolean not null default false;

create table zz_promo_code_allowed_users (
  promo_code_id uuid not null references zz_promo_codes(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  created_at    timestamptz not null default now(),
  primary key (promo_code_id, user_id)
);

-- Server-only, like zz_promo_codes: RLS on, no policies, so clients can never
-- read or write the allow-list. Edge functions use the service role key.
alter table zz_promo_code_allowed_users enable row level security;
