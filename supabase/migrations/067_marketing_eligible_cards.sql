-- Powers the admin "Add Marketing Cards" page. cards.sender_id stopped being a
-- foreign key in 057, so PostgREST can no longer embed users through cards.
-- This does the join, the already-in-marketing exclusion, the ordering and
-- the paging in one query. total_count is the full eligible count on every
-- row. Service role only (the admin pages); not callable by app clients.

create or replace function marketing_eligible_cards(p_limit int, p_offset int)
returns table (
  id               uuid,
  thumbnail_url    text,
  design_features  text,
  sent_at          timestamptz,
  total_count      bigint
)
language sql
stable
set search_path = public
as $$
  select c.id, c.thumbnail_url, c.design_features, c.sent_at, count(*) over () as total_count
  from cards c
  join users u on u.id = c.sender_id
  where u.allow_marketing_use
    and not exists (select 1 from marketing_cards m where m.card_id = c.id)
  order by c.sent_at desc
  limit p_limit offset p_offset;
$$;

revoke all on function marketing_eligible_cards(int, int) from public, anon, authenticated;
grant execute on function marketing_eligible_cards(int, int) to service_role;

-- The page orders by newest first; without this the database sorts every
-- eligible card on each page load.
create index if not exists cards_sent_at_idx on cards (sent_at desc);
