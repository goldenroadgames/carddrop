-- Terms acceptance. users.terms_version is the "Last updated" date of the Terms
-- text the person agreed to (read by the accept-terms function from the live
-- document); terms_accepted_at is when. zz_config.terms_required_version is the
-- threshold: only raise it for a MATERIAL change to the Terms or Privacy Policy
-- (then everyone who accepted an earlier version is asked again before their
-- next send). A person is fine when terms_version >= terms_required_version.
-- Versions are YYYY-MM-DD, so plain text comparison works.
alter table users
  add column if not exists terms_accepted_at timestamptz,
  add column if not exists terms_version     text;

insert into zz_config (key, value, description) values
  ('terms_required_version', '2026-10-12',
   'Terms/Privacy version (YYYY-MM-DD) every sender must have accepted. Raise ONLY for a material change; older acceptances are then asked again before the next send.')
on conflict (key) do nothing;
