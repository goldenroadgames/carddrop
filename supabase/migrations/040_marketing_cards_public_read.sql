-- marketing_cards had RLS enabled (036) but zero policies, on the reasoning
-- it'd only ever be read via the admin webapp's service-role key (which
-- bypasses RLS). That missed the iOS "Get Inspired" gallery, which reads it
-- with the regular anon/auth key — subject to RLS, so with no policy at all
-- every query silently returned zero rows. marketing_cards is deliberately
-- built to hold nothing but public-safe, non-PII data (front image +
-- design_features only), so a public read policy is exactly appropriate.
create policy "marketing_cards: public read"
  on marketing_cards for select
  using (true);
