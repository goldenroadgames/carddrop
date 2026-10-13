-- A sender whose last `complaint_strikes_to_ban` (3) reported cards all fall
-- within this many hours is suspended as FINAL at once (no appeal; devices
-- marked permanent; the owner is emailed). 0 turns the rule off. A slower third
-- report gives the ordinary suspension, with an appeal.
insert into zz_config (key, value, description) values
  ('complaint_rapid_final_hours', '72', 'Hours: if the 3 reported cards that cause a suspension fall within this span, the suspension is final (0 = off)')
on conflict (key) do nothing;
