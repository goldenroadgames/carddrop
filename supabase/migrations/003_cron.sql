-- CardDrop pg_cron setup
-- Run AFTER 001_schema.sql
-- Requires pg_cron extension (enable in Supabase: Database > Extensions > pg_cron)
-- Safe to re-run: unschedules existing jobs before re-adding them

-- Unschedule existing jobs if present (no-ops if they don't exist)
select cron.unschedule(jobname)
from cron.job
where jobname in ('reset-monthly-sends', 'keep-alive');

-- Reset monthly send counts on the 1st of each month at midnight UTC
select cron.schedule(
  'reset-monthly-sends',
  '1 0 1 * *',
  $$ update users set sends_this_month = 0; $$
);

-- Keep-alive: prevents Supabase free tier from pausing the project after 7 days inactivity
select cron.schedule(
  'keep-alive',
  '0 6 * * *',  -- daily at 6am UTC
  $$ select 1; $$
);
