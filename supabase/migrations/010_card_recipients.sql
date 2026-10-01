-- Create card_recipients table
create table card_recipients (
  id          uuid primary key default gen_random_uuid(),
  card_id     uuid not null references cards(id) on delete cascade,
  first_name  text,
  last_name   text,
  street      text,
  city        text,
  state       text,
  zip         text,
  country     text,
  email       text,
  phone       text,
  created_at  timestamptz not null default now()
);

create index on card_recipients(card_id);

-- Migrate existing recipient data from cards into card_recipients
insert into card_recipients (card_id, first_name, email, phone)
select id, recipient_name, recipient_email, recipient_phone
from cards
where recipient_name  is not null
   or recipient_email is not null
   or recipient_phone is not null;

-- Drop recipient columns from cards
alter table cards drop column if exists recipient_name;
alter table cards drop column if exists recipient_email;
alter table cards drop column if exists recipient_phone;
