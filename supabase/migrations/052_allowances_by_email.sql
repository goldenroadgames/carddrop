-- Free-postcard allowances are now keyed by EMAIL, not user id (see 048/049).
--
-- Why: you can list a friend before they have an account. At checkout the
-- edge functions look up the caller's VERIFIED email (email_confirmed_at, or
-- an Apple identity, which Apple has already verified) in this table. No user
-- id is stored, so nothing has to be filled in after signup, and a grant
-- follows the email address.
--
-- Emails are stored lowercase (enforced), and the functions lowercase the
-- caller's email before matching. For "Hide My Email" Apple users, list the
-- @privaterelay.appleid.com address shown on their Profile screen.
--
-- To grant (hard cap of 5/month still enforced, 1-2 typical):
--   insert into zz_account_allowances (email, free_postcards_per_month, expires_on, note)
--   values ('mom@example.com', 2, '2027-12-31', 'Mom');

alter table zz_account_allowances add column email text;

-- Carry over existing grants: copy each account's email, lowercased.
update zz_account_allowances z
set email = lower(a.email)
from auth.users a
where a.id = z.user_id;

-- A grant whose account has no email (e.g. an anonymous test user) can't be
-- matched by email, so it can't be carried over.
delete from zz_account_allowances where email is null;

alter table zz_account_allowances drop constraint zz_account_allowances_pkey;
alter table zz_account_allowances drop column user_id;

alter table zz_account_allowances
  alter column email set not null,
  add constraint zz_account_allowances_email_lowercase check (email = lower(email)),
  add primary key (email);
