-- Add sender address snapshot columns to card_recipients so the return address
-- (editable per send, including resends) is persisted alongside each recipient row.
-- Deliberately excludes sender_email/sender_phone — see project memory for rationale;
-- CardDrop can't know which of the user's accounts a native Mail/Messages compose
-- actually sent from, and email/phone aren't relevant for physical LOB sends.

alter table card_recipients add column if not exists sender_street  text;
alter table card_recipients add column if not exists sender_city    text;
alter table card_recipients add column if not exists sender_state  text;
alter table card_recipients add column if not exists sender_zip     text;
alter table card_recipients add column if not exists sender_country text;
