-- Score-based moderation thresholds, tunable without an app release (same
-- pattern as the send_limit_* keys in zz_config, migration 007/029).
--
-- OpenAI's moderation API returns both a boolean `categories.<name>` (their
-- own internal cutoff) and a 0.0-1.0 `category_scores.<name>` confidence.
-- ModerationService previously hard-blocked on the boolean alone, which
-- proved too strict for "harassment" in a novelty-postcard app where mild
-- jabs ("you really smell bad") are the whole point — that boolean fired on
-- borderline text OpenAI itself only gave a moderate confidence score to.
--
-- A category with no threshold row here keeps the old strict behavior
-- (blocks whenever OpenAI's own boolean is true) — see ModerationService's
-- default-to-0 fallback. Only relaxing the one category that's actually
-- been a problem; hate/self-harm/sexual/violence etc. stay maximally strict.
insert into zz_config (key, value, description) values
  ('moderation_threshold_harassment', '0.85', 'Minimum OpenAI moderation category_scores.harassment to hard-block card text (0.0-1.0). Categories with no threshold row block on OpenAI''s own boolean flag alone.')
on conflict (key) do nothing;
