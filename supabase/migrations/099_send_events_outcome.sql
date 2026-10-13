-- Record how each send-card call ended, so the admin pages can show an exact
-- count of completed digital sends (send-card = the card was checked, published
-- and its link returned) next to all attempts (which include resends, sends
-- the content check refused, and calls stopped by a limit).
--   sent     the card passed every check and the link was returned
--   refused  the content check refused it
--   (null)   any other ending (a limit, an error), and every row from before this
-- Mailed postcards are counted separately, from physical_orders.
alter table send_events add column if not exists outcome text
  check (outcome in ('sent', 'refused'));
