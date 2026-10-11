-- One-time: hide cards that were reported before reported_at existed (058).
-- Idempotent; only touches cards with a complaint and no reported_at.
update cards
set reported_at = c.created_at
from card_complaints c
where c.card_id = cards.id
  and cards.reported_at is null;
