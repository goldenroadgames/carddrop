-- CardDrop lifetime send counter
-- Run AFTER 001_schema.sql
--
-- Adds sends_lifetime to track total sends across all time.
-- Used to enforce lifetime limits for anonymous and unverified tiers.
-- Unlike sends_this_month, this column is never reset by cron.

alter table users
  add column if not exists sends_lifetime int not null default 0;
