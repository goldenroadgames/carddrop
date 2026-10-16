-- Marketing queue: by default only cards that were mailed or that got a
-- reaction or reply; p_all = true shows every eligible card. Supersedes 107
-- (same exclusions: sender allows marketing, not reported / held / deleted /
-- purged, sender not suspended, not already picked) and adds the p_all switch,
-- so the function gets a third argument.
drop function if exists marketing_eligible_cards(int, int);

create or replace function marketing_eligible_cards(p_limit int, p_offset int, p_all boolean default false)
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
    and c.reported_at is null
    and not c.legal_hold
    and c.deleted_at is null
    and c.purged_at is null
    and not exists (select 1 from account_bans b where b.user_id = c.sender_id and b.reinstated_at is null)
    and not exists (select 1 from marketing_cards m where m.card_id = c.id)
    and (
      p_all
      or exists (select 1 from physical_orders o
                 where o.card_id = c.id and o.status in ('submitted_to_lob', 'printed', 'mailed', 'delivered'))
      or exists (select 1 from reactions r where r.card_id = c.id)
      or exists (select 1 from replies rp where rp.card_id = c.id)
    )
  order by c.sent_at desc
  limit p_limit offset p_offset;
$$;

revoke all on function marketing_eligible_cards(int, int, boolean) from public, anon, authenticated;
grant execute on function marketing_eligible_cards(int, int, boolean) to service_role;
