-- A card that receives a complaint is hidden: the web shows it as unavailable,
-- the app drops it from the sender's lists, and the sender can't delete,
-- resend or copy it (only deleting the whole account removes it). The row and
-- its files are kept as evidence until the 12-month retention sweep.
alter table cards add column if not exists reported_at timestamptz;

create index if not exists cards_reported_at_idx
  on cards (reported_at) where reported_at is not null;
