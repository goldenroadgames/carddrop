-- Distinguishes what role a saved address plays for its owner: their own
-- canonical return address ("profile"), a previously-used "from" address on
-- some send ("sender"), or a saved "to" address ("recipient"). A user has at
-- most one "profile" row; when it's replaced, the app reassigns the old row
-- to "sender" rather than deleting it. Existing rows predate this concept and
-- are backfilled as "recipient" (the most general bucket) — the app assigns
-- real types going forward.

alter table user_address_book
  add column address_type text not null default 'recipient'
    check (address_type in ('profile', 'sender', 'recipient'));

update user_address_book set address_type = 'recipient';

alter table user_address_book alter column address_type drop default;

-- At most one "profile" row per user.
create unique index user_address_book_one_profile_per_user
  on user_address_book(user_id)
  where address_type = 'profile';

create index on user_address_book(user_id, address_type);
