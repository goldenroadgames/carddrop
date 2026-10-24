-- marketing_cards is publicly readable (migration 040) so the app's "Get
-- Inspired" gallery can list it, but that also exposed sender_id and
-- original_sent_at to anyone holding the public key. Limit anonymous and
-- signed-in reads to the columns the gallery uses (in_inspire is needed
-- because the gallery filters on it). The admin pages use the service role,
-- which these grants do not affect.
-- RUN ONLY AFTER the app build without sender_id (InspireGalleryStore /
-- InspireCard) is in use, or the gallery query fails with permission denied.
revoke select on marketing_cards from anon, authenticated;
grant select (card_id, is_portrait, design_features, added_to_marketing_at, in_inspire)
  on marketing_cards to anon, authenticated;
