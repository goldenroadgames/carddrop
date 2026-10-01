-- Marketing curation pool. A card selected in the admin "Marketing Photo
-- Review" tool gets its row (non-PII fields only) and its card-images
-- assets copied here, fully decoupled from the original `cards` row (no FK
-- to cards or users) so normal expiry/cleanup of user data can never touch
-- marketing material once selected. See project memory
-- project_marketing_use_feature.md for the fuller history/decision trail.
-- Front only — the back bakes in the sender's actual personal message as
-- pixels, never used for marketing. No image URL columns: marketing-cards
-- paths are anonymized (`{card_id}.jpg` / `{card_id}_thumb.jpg`, no sender
-- segment), so both are fully derivable from card_id + the fixed bucket
-- name at read time — nothing to store.
create table marketing_cards (
  card_id                uuid primary key,       -- copied from cards.id — not a FK, deliberately decoupled
  sender_id              uuid not null,           -- copied from cards.sender_id — not a FK either
  is_portrait            boolean not null,
  design_features        text,
  original_sent_at       timestamptz not null,
  added_to_marketing_at  timestamptz not null default now()
);

-- Service-role only — no RLS policies at all. This table is only ever
-- written/read by the admin tool (via the service-role key), never by the
-- app or the public site.
alter table marketing_cards enable row level security;

-- New public storage bucket for the copied assets — anonymized filenames
-- (cardID only, no sender path segment), since this pool may end up
-- browsable more broadly later (marketing site/social/ads).
insert into storage.buckets (id, name, public)
values ('marketing-cards', 'marketing-cards', true)
on conflict (id) do nothing;

create policy "marketing-cards: auth users can upload"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'marketing-cards');

create policy "marketing-cards: auth users can update"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'marketing-cards')
  with check (bucket_id = 'marketing-cards');

create policy "marketing-cards: public read"
  on storage.objects for select
  using (bucket_id = 'marketing-cards');
