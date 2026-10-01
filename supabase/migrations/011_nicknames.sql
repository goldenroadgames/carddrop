-- Add casual nicknames for sender/recipient, replacing unused formal name columns on cards

alter table users add column if not exists sender_nickname text;

alter table cards drop column if exists recipient_first_name;
alter table cards drop column if exists recipient_last_name;

alter table cards add column if not exists sender_nickname text;
alter table cards add column if not exists recipient_nickname text;
