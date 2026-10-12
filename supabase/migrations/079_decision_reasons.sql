-- Reasons for admin decisions on suspensions (shown as a dropdown on the
-- appeals controls and on "Make final"). Edit the list in the Supabase table
-- viewer: add rows, rename labels, reorder with sort_order, or set active =
-- false to retire one (old decisions keep the label they were made with).
-- Internal only: service role, no client access.
create table if not exists decision_reasons (
  id          uuid primary key default gen_random_uuid(),
  label       text not null unique,
  applies_to  text not null check (applies_to in ('reinstated', 'denied', 'both')),
  sort_order  int not null default 0,
  active      boolean not null default true
);
alter table decision_reasons enable row level security;
revoke all on decision_reasons from anon, authenticated;

insert into decision_reasons (label, applies_to, sort_order) values
  ('Likely a moderation false positive',          'reinstated', 10),
  ('First offense, warning given',                'reinstated', 20),
  ('Appeal was credible',                         'reinstated', 30),
  ('Reported card did not violate our terms',     'reinstated', 40),
  ('Admin error',                                 'reinstated', 50),
  ('Repeated harassment of recipients',           'denied',     110),
  ('Sexual or explicit content',                  'denied',     120),
  ('Violent or threatening content',              'denied',     130),
  ('Hate content',                                'denied',     140),
  ('Evaded an earlier suspension',                'denied',     150),
  ('Sent cards show a pattern of abuse',          'denied',     160),
  ('Appeal did not address the problem',          'denied',     170),
  ('Repeated blocked content',                    'denied',     180),
  ('Other (see note)',                            'both',       900)
on conflict (label) do nothing;

-- The reason chosen for an appeal decision, and for a hand-made final
-- suspension. Internal: not in the clients' column grant on ban_reviews.
alter table ban_reviews add column if not exists reason text;
alter table account_bans add column if not exists final_reason text;
