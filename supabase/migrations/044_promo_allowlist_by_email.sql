-- Lets a restricted promo code's allow-list hold an EMAIL for someone who
-- hasn't signed up yet (see 043_promo_free_and_restricted.sql). A row now has
-- a user_id (existing account), an email (matched against the caller's
-- verified account email), or both.
--
-- The edge functions only honor an email match when the caller's email is
-- verified, so typing someone's email onto a code never lets a stranger
-- claim it by signing up with an address they don't own.
--
-- The old primary key (promo_code_id, user_id) can't stay because user_id is
-- now nullable, so rows get their own id and uniqueness moves to partial
-- unique indexes.

alter table zz_promo_code_allowed_users
  add column id    uuid not null default gen_random_uuid(),
  add column email text;

alter table zz_promo_code_allowed_users drop constraint zz_promo_code_allowed_users_pkey;
alter table zz_promo_code_allowed_users add primary key (id);
alter table zz_promo_code_allowed_users alter column user_id drop not null;

alter table zz_promo_code_allowed_users
  add constraint zz_promo_code_allowed_users_who check (user_id is not null or email is not null);

create unique index zz_promo_code_allowed_users_user_unique
  on zz_promo_code_allowed_users (promo_code_id, user_id) where user_id is not null;
create unique index zz_promo_code_allowed_users_email_unique
  on zz_promo_code_allowed_users (promo_code_id, lower(email)) where email is not null;
