-- Tracks how a card was sent to a given recipient row, so "Send history" can
-- show the mode (email vs text) rather than guessing from which of
-- email/phone happens to be populated (a text sent to an email-style
-- iMessage handle populates the `email` column too, so that alone can't
-- distinguish the two). Existing rows predate this column and stay NULL —
-- the app falls back to a generic "Digital" label for those.
alter table card_recipients add column if not exists send_method text;
