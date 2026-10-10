-- Optional end date for an account's free-postcard allowance (see 048).
-- expires_on is the LAST day the allowance works, inclusive: it runs through
-- that whole day (UTC date), then the account goes back to normal pricing.
-- Null = no expiry; it runs until the row is deleted. Example:
--   update zz_account_allowances set expires_on = '2026-12-31' where user_id = '<id>';

alter table zz_account_allowances
  add column expires_on date;
