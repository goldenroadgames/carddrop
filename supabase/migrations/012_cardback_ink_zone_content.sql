-- Reference tables for the digital-only ink-free-zone content on the card back:
-- an optional salutation/closing greeting combo, and an optional standalone phrase.
-- Both are client-selectable per card; physical (LOB) sends render this zone blank
-- so LOB can print the mailing address there instead.

-- ==============================
-- TABLES
-- ==============================

create table cardback_greetings (
  id                   uuid primary key default gen_random_uuid(),
  salutation_template  text not null,   -- e.g. 'Dear {recipient},'  (empty string = no salutation)
  closing_template     text not null,   -- e.g. 'Love, {sender}'
  sort_order           int not null,
  created_at           timestamptz not null default now()
);

create index on cardback_greetings(sort_order);

create table cardback_phrases (
  id         uuid primary key default gen_random_uuid(),
  category   text not null,   -- 'Basic' | 'Quirky' | 'Romantic'
  text       text not null,
  sort_order int not null,
  created_at timestamptz not null default now()
);

create index on cardback_phrases(sort_order);

-- ==============================
-- SEED VALUES
-- ==============================

insert into cardback_greetings (salutation_template, closing_template, sort_order) values
  ('Dear {recipient},',    'Love, {sender}',         1),
  ('{recipient},',         'Always, {sender}',       2),
  ('My {recipient},',      'Forever yours, {sender}', 3),
  ('{recipient} —',        '— {sender}',             4),
  ('',                     '❤️ {sender}',            5),
  ('Dearest {recipient},', 'All my love, {sender}',  6),
  ('{recipient},',         'XOXO {sender}',          7);

insert into cardback_phrases (category, text, sort_order) values
  ('Basic', 'I Love You.', 1),
  ('Basic', 'I Miss You.', 2),
  ('Basic', 'It is what it is.', 3),
  ('Basic', 'Just because.', 4),
  ('Basic', 'No reason.', 5),
  ('Basic', 'P.S. I love you.', 6),
  ('Basic', 'Thinking of you.', 7),
  ('Basic', 'Wanna binge?', 8),
  ('Basic', 'Wish you were here.', 9),
  ('Basic', 'With love, from me to you.', 10),
  ('Basic', 'You make everything better.', 11),
  ('Basic', 'You''re in my heart.', 12),
  ('Basic', 'You''re my best friend.', 13),
  ('Basic', 'You''re my favorite.', 14),
  ('Basic', 'You''re the one that I want. Woo hoo hoo!', 15),
  ('Quirky', 'Can I check your tires?', 1),
  ('Quirky', 'I keep your picture in my lunchbox.', 2),
  ('Quirky', 'I want to be your Thursday afternoon.', 3),
  ('Quirky', 'I want to shampoo you.', 4),
  ('Quirky', 'I want to sit beside you on the bus.', 5),
  ('Quirky', 'I''ll iron your shirts.', 6),
  ('Quirky', 'Let''s grow vegetables and argue about it.', 7),
  ('Quirky', 'Let''s sit in the back of the cab forever.', 8),
  ('Quirky', 'Let''s watch something we''ve both already seen.', 9),
  ('Quirky', 'Meatball Sandwich?', 10),
  ('Quirky', 'Remember when we couldn''t stop laughing and couldn''t remember why?', 11),
  ('Quirky', 'Remember when we stayed up way too late?', 12),
  ('Quirky', 'Shovel early and often.', 13),
  ('Quirky', 'You''re my favorite weirdo.', 14),
  ('Quirky', 'You''re my kind of strange.', 15),
  ('Quirky', 'You''re the reason I check my phone.', 16),
  ('Romantic', 'For the thousandth time, as you wish.', 1),
  ('Romantic', 'I can''t help falling in love with you.', 2),
  ('Romantic', 'I saved you the last bite.', 3),
  ('Romantic', 'I want to be there for the boring parts.', 4),
  ('Romantic', 'I want to be your emergency contact.', 5),
  ('Romantic', 'I want to dance with you in the refrigerator light.', 6),
  ('Romantic', 'I want to learn all your faces.', 7),
  ('Romantic', 'I will follow you into the dark.', 8),
  ('Romantic', 'I''ll drive you to the airport.', 9),
  ('Romantic', 'Let''s be boring together.', 10),
  ('Romantic', 'Let''s get lost together.', 11),
  ('Romantic', 'Let''s grow old disgracefully.', 12),
  ('Romantic', 'Let''s stay in tonight.', 13),
  ('Romantic', 'Meet me at the place.', 14),
  ('Romantic', 'Remember when we didn''t know each other? Me neither.', 15),
  ('Romantic', 'The remote is yours.', 16),
  ('Romantic', 'You''re my favorite distraction.', 17),
  ('Romantic', 'You''re my person.', 18),
  ('Romantic', 'You''re the best part of my day.', 19);

-- ==============================
-- RLS
-- ==============================

alter table cardback_greetings enable row level security;
create policy "cardback_greetings: public read" on cardback_greetings for select using (true);

alter table cardback_phrases enable row level security;
create policy "cardback_phrases: public read" on cardback_phrases for select using (true);
-- No client writes — content managed via migrations / service role.
