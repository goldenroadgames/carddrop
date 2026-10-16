-- Friendly moderation labels in zz_config, one per OpenAI category.
-- Row key is moderation_label_ plus OpenAI's category name. moderation.ts reads
-- these first, then falls back to its built-in LABELS map, then the raw name.
insert into zz_config (key, value, description) values
  ('moderation_label_harassment', 'harassment', 'Friendly name shown to the user and in admin when OpenAI flags harassment. Takes effect on the next moderation call, no redeploy.'),
  ('moderation_label_harassment/threatening', 'threatening harassment', 'Friendly name shown to the user and in admin when OpenAI flags harassment/threatening. Takes effect on the next moderation call, no redeploy.'),
  ('moderation_label_hate', 'hate speech', 'Friendly name shown to the user and in admin when OpenAI flags hate. Takes effect on the next moderation call, no redeploy.'),
  ('moderation_label_hate/threatening', 'threatening hate speech', 'Friendly name shown to the user and in admin when OpenAI flags hate/threatening. Takes effect on the next moderation call, no redeploy.'),
  ('moderation_label_illicit', 'illicit content', 'Friendly name shown to the user and in admin when OpenAI flags illicit. Takes effect on the next moderation call, no redeploy.'),
  ('moderation_label_illicit/violent', 'violent illicit content', 'Friendly name shown to the user and in admin when OpenAI flags illicit/violent. Takes effect on the next moderation call, no redeploy.'),
  ('moderation_label_self-harm', 'self-harm', 'Friendly name shown to the user and in admin when OpenAI flags self-harm. Takes effect on the next moderation call, no redeploy.'),
  ('moderation_label_self-harm/intent', 'self-harm', 'Friendly name shown to the user and in admin when OpenAI flags self-harm/intent. Takes effect on the next moderation call, no redeploy.'),
  ('moderation_label_self-harm/instructions', 'self-harm', 'Friendly name shown to the user and in admin when OpenAI flags self-harm/instructions. Takes effect on the next moderation call, no redeploy.'),
  ('moderation_label_sexual', 'sexually explicit content', 'Friendly name shown to the user and in admin when OpenAI flags sexual. Takes effect on the next moderation call, no redeploy.'),
  ('moderation_label_sexual/minors', 'content involving minors', 'Friendly name shown to the user and in admin when OpenAI flags sexual/minors. Takes effect on the next moderation call, no redeploy.'),
  ('moderation_label_violence', 'violent content', 'Friendly name shown to the user and in admin when OpenAI flags violence. Takes effect on the next moderation call, no redeploy.'),
  ('moderation_label_violence/graphic', 'graphic violence', 'Friendly name shown to the user and in admin when OpenAI flags violence/graphic. Takes effect on the next moderation call, no redeploy.')
on conflict (key) do nothing;
