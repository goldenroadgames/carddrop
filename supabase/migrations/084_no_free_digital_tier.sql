-- No free tier: digital sends require a verified account (Apple sign-in or
-- email OTP). Anonymous and unverified users get 0 sends. send-card still
-- enforces this server-side; the app now gates the send buttons up front.
update zz_config set value = '0'
where key in (
  'send_limit_anonymous_monthly',
  'send_limit_anonymous_lifetime',
  'send_limit_unverified_monthly',
  'send_limit_unverified_lifetime'
);
