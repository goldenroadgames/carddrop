-- Add last_name to users (sender profile)
alter table users add column if not exists last_name text;

-- Add first/last name to cards (recipient at send time)
alter table cards add column if not exists recipient_first_name text;
alter table cards add column if not exists recipient_last_name  text;
