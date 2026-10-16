-- Profanity blocklist, checked by _shared/moderation.ts alongside OpenAI.
-- moderation_blocklist: comma-separated words, whole-word match, case-insensitive.
-- Swaps (@ $ 1 ! 0 3 5 4), a * for one letter, stretched letters and spaced-out
-- single letters are handled in code; missing-vowel spellings must be listed here.
-- A hit blocks the text with the label "profanity" and records NO strike.
-- moderation_blocklist_enabled: 'true' / 'false'. Edits apply on the next check.
insert into zz_config (key, value, description) values
  ('moderation_blocklist', 'fuck, fucking, fucker, fucked, motherfucker, fck, fk, fuk, fuq, fcking, fckin, fcker, mthrfckr, shit, bullshit, sht, shyt, bullsht, bitch, bitches, btch, bch, btches, asshole, asshle, ass, azz, arse, bastard, bstrd, dickhead, dckhead, cock, cck, cunt, cnt, pussy, pssy, prick, prck, twat, twt, wanker, wnkr, slut, slt, whore, whr, douche, douchebag, dche', 'Profanity blocklist: comma-separated words, matched as whole words (case-insensitive; common character swaps, a * for one letter and spaced-out letters are caught automatically; list missing-vowel spellings yourself). A hit blocks the text but records no strike.'),
  ('moderation_blocklist_enabled', 'true', 'true = check the profanity blocklist (moderation_blocklist); false = skip it.')
on conflict (key) do nothing;
