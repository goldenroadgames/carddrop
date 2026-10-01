-- Captures the informal "To" nickname entered on the Names step (e.g. "Mom")
-- alongside the formal first/last name on each card_recipients row, so send
-- history can show both without joining back to the cards table's
-- recipient_nickname (which is per-card, not per-recipient).
alter table card_recipients add column if not exists nickname text;
