-- Restricted promo codes can also admit anyone whose VERIFIED account email
-- is at a listed domain (e.g. 'nyu.edu', which also matches subdomains such as
-- 'stern.nyu.edu' but never a lookalike such as 'notnyu.edu'). See
-- 043/044. Stored lowercase, no '@'. Empty array = no domain rule.
--
-- Rule enforced by validate-promo-code / create-postcard-payment-intent:
-- an unrestricted code is open to anyone (subject to its limits); a restricted
-- code needs a verified email AND (on the allow-list by user id, on the
-- allow-list by email, or at an allowed domain).

alter table zz_promo_codes
  add column allowed_email_domains text[] not null default '{}';
