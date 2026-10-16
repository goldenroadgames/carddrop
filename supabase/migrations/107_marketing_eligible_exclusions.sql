-- Reported, legal-hold, deleted and purged cards, and cards from suspended
-- senders (an account_bans row not yet reinstated), are no longer offered for
-- marketing curation (the pick step re-checks the same columns).
-- Same signature and output as 067, so create or replace is enough.
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
    and c.reported_at is null
    and not c.legal_hold
    and c.deleted_at is null
    and c.purged_at is null
    and not exists (select 1 from account_bans b where b.user_id = c.sender_id and b.reinstated_at is null)
    and not exists (select 1 from marketing_cards m where m.card_id = c.id)
  order by c.sent_at desc
  limit p_limit offset p_offset;
$$;

revoke all on function marketing_eligible_cards(int, int) from public, anon, authenticated;
grant execute on function marketing_eligible_cards(int, int) to service_role;
