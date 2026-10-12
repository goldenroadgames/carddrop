-- Per-card legal hold. A held card (reported or not) is never deleted by the
-- sweeper, the sender, an account deletion or a final-suspension cleanup, and
-- its replies, send log, complaints and order snapshots are kept too. Set and
-- released from the admin Reported Cards page, or by hand:
--   update cards set legal_hold = true, legal_hold_at = now() where id = '<card id>';
-- Clients cannot update cards (no update policy), so only the service role
-- changes this.
alter table cards
  add column if not exists legal_hold boolean not null default false,
  add column if not exists legal_hold_at timestamptz;

create index if not exists cards_legal_hold_idx on cards (id) where legal_hold;
