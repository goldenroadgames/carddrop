-- One row per physical-mail (LOB) attempt. Kept separate from
-- card_recipients (which is digital-send history) since a physical order
-- has a materially different lifecycle (payment, LOB status, tracking).
-- Address fields are a SNAPSHOT taken at order time, not a live join to
-- user_address_book, so editing/deleting a saved address later never
-- changes what was actually mailed; the address_book_id columns are just a
-- convenience link back to which saved entry (if any) was used.

create table physical_orders (
  id                        uuid primary key default gen_random_uuid(),
  card_id                   uuid not null references cards(id) on delete cascade,
  sender_id                 uuid not null references auth.users(id),

  recipient_first_name      text,
  recipient_last_name       text,
  recipient_street          text,
  recipient_city            text,
  recipient_state           text,
  recipient_zip             text,
  recipient_country         text,

  sender_first_name         text,
  sender_last_name          text,
  sender_street             text,
  sender_city                text,
  sender_state              text,
  sender_zip                text,
  sender_country            text,

  recipient_address_book_id uuid references user_address_book(id),
  sender_address_book_id    uuid references user_address_book(id),

  card_size                 text not null check (card_size in ('4x6', '6x9')),

  stripe_payment_intent_id  text,
  amount_cents              integer,
  currency                  text not null default 'usd',

  status                    text not null default 'pending_payment'
    check (status in (
      'pending_payment', 'paid', 'submitted_to_lob',
      'printed', 'mailed', 'delivered', 'failed', 'refunded'
    )),
  error_message              text,

  lob_id                     text,
  lob_tracking_number        text,
  lob_expected_delivery_date date,

  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now()
);

create index on physical_orders(card_id);
create index on physical_orders(sender_id);

alter table physical_orders enable row level security;

-- Sender reads their own orders. No insert/update/delete policy for
-- authenticated users — payment and LOB status must only ever be written
-- by edge functions using the service role key, never directly by the
-- client, so those stay unwritable via RLS.
create policy "physical_orders: sender reads own"
  on physical_orders for select
  using (auth.uid() = sender_id);
