-- Records content that the automated moderation blocked, so repeat offenders
-- can be suspended (see _shared/contentBlocks.ts). The content itself is never
-- stored: only who (account + device), whether it was a photo or text, which
-- categories OpenAI flagged, and when. `counted` marks the blocks that count
-- toward a suspension: blocked photos, and harassment flags (not other
-- language, which people can simply clean up). `fingerprints` holds a one-way hash of
-- EACH flagged text/photo: a block counts only if it contains a flagged item
-- not already flagged for this user in the last 24 hours.
--
-- Service role only (RLS on, no policies, no grants). No foreign key on
-- user_id: the row has no personal content and is kept 12 months for abuse
-- prevention even if the account is deleted (sweep-deleted-cards deletes it).
create table if not exists content_blocks (
  id           bigint generated always as identity primary key,
  user_id      uuid,
  device_uuid  uuid,
  kind         text not null check (kind in ('photo', 'text')),
  categories   text[] not null default '{}',
  counted      boolean not null default false,
  fingerprints text[] not null default '{}',
  created_at   timestamptz not null default now()
);

create index if not exists content_blocks_user_counted_idx
  on content_blocks (user_id, created_at desc) where counted;
create index if not exists content_blocks_created_idx
  on content_blocks (created_at);

alter table content_blocks enable row level security;
revoke all on content_blocks from anon, authenticated;

-- Tunable without a deploy. Warnings start 2 blocks before either limit.
insert into zz_config (key, value, description) values
  ('content_block_limit_24h', '6',  'Counted content blocks in 24 hours that suspend an account'),
  ('content_block_limit_30d', '15', 'Counted content blocks in 30 days that suspend an account')
on conflict (key) do nothing;
