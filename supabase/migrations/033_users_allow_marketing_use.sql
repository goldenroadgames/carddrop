-- Backs the Privacy Policy's "Marketing Use of Card Designs" opt-out (Section 5).
-- Defaults to true per that policy: enabled by default for account holders,
-- toggle-off only stops future card selection, not cards already flagged.
alter table users
  add column if not exists allow_marketing_use boolean not null default true;
