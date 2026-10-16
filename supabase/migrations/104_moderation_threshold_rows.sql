-- Explicit moderation threshold rows for every OpenAI moderation category.
-- 031 only created one for "harassment"; a category with no row is treated as
-- 0 (block on OpenAI's own flag), so a row of '0' behaves exactly the same as
-- no row. Seeding them all makes every category visible and editable in
-- zz_config (take effect on the next moderation call, no redeploy). The row key
-- is moderation_threshold_ plus OpenAI's category name. harassment keeps its
-- existing 0.85 (on conflict do nothing).
insert into zz_config (key, value, description) values
  ('moderation_threshold_harassment/threatening', '0', 'Minimum OpenAI moderation score for harassment/threatening to block (0.0-1.0). 0 = block on OpenAI''s own flag alone (strictest). A higher value lets lower-scoring flags through; it can never block more than OpenAI''s flag.'),
  ('moderation_threshold_hate', '0', 'Minimum OpenAI moderation score for hate to block (0.0-1.0). 0 = block on OpenAI''s own flag alone (strictest). A higher value lets lower-scoring flags through; it can never block more than OpenAI''s flag.'),
  ('moderation_threshold_hate/threatening', '0', 'Minimum OpenAI moderation score for hate/threatening to block (0.0-1.0). 0 = block on OpenAI''s own flag alone (strictest). A higher value lets lower-scoring flags through; it can never block more than OpenAI''s flag.'),
  ('moderation_threshold_illicit', '0', 'Minimum OpenAI moderation score for illicit to block (0.0-1.0). 0 = block on OpenAI''s own flag alone (strictest). A higher value lets lower-scoring flags through; it can never block more than OpenAI''s flag.'),
  ('moderation_threshold_illicit/violent', '0', 'Minimum OpenAI moderation score for illicit/violent to block (0.0-1.0). 0 = block on OpenAI''s own flag alone (strictest). A higher value lets lower-scoring flags through; it can never block more than OpenAI''s flag.'),
  ('moderation_threshold_self-harm', '0', 'Minimum OpenAI moderation score for self-harm to block (0.0-1.0). 0 = block on OpenAI''s own flag alone (strictest). A higher value lets lower-scoring flags through; it can never block more than OpenAI''s flag.'),
  ('moderation_threshold_self-harm/intent', '0', 'Minimum OpenAI moderation score for self-harm/intent to block (0.0-1.0). 0 = block on OpenAI''s own flag alone (strictest). A higher value lets lower-scoring flags through; it can never block more than OpenAI''s flag.'),
  ('moderation_threshold_self-harm/instructions', '0', 'Minimum OpenAI moderation score for self-harm/instructions to block (0.0-1.0). 0 = block on OpenAI''s own flag alone (strictest). A higher value lets lower-scoring flags through; it can never block more than OpenAI''s flag.'),
  ('moderation_threshold_sexual', '0', 'Minimum OpenAI moderation score for sexual to block (0.0-1.0). 0 = block on OpenAI''s own flag alone (strictest). A higher value lets lower-scoring flags through; it can never block more than OpenAI''s flag.'),
  ('moderation_threshold_sexual/minors', '0', 'Minimum OpenAI moderation score for sexual/minors to block (0.0-1.0). 0 = block on OpenAI''s own flag alone (strictest). A higher value lets lower-scoring flags through; it can never block more than OpenAI''s flag.'),
  ('moderation_threshold_violence', '0', 'Minimum OpenAI moderation score for violence to block (0.0-1.0). 0 = block on OpenAI''s own flag alone (strictest). A higher value lets lower-scoring flags through; it can never block more than OpenAI''s flag.'),
  ('moderation_threshold_violence/graphic', '0', 'Minimum OpenAI moderation score for violence/graphic to block (0.0-1.0). 0 = block on OpenAI''s own flag alone (strictest). A higher value lets lower-scoring flags through; it can never block more than OpenAI''s flag.')
on conflict (key) do nothing;
