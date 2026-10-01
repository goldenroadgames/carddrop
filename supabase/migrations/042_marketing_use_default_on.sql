-- Reverts migration 041's default: marketing use of card designs is opted-IN
-- automatically for new accounts again (Privacy Policy Section 5 / ToS "Marketing
-- use" restored to the 26Sep26 wording: enabled by default, can be turned off
-- in Settings).
--
-- Only the column default changes. No backfill: rows already set to false
-- (anonymous accounts and existing opt-outs from 041) are left as they are.

alter table users
  alter column allow_marketing_use set default true;
