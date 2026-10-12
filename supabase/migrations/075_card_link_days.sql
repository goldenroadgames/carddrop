-- Card links no longer depend on a paid "unlimited" tier. Every card link
-- expires card_link_days after it is sent (send-card), and each real web view
-- pushes the expiry out card_link_extend_days from that moment (extend-card-link),
-- with no cap. Both are tunable without a deploy. The help screens read
-- card_link_days for the "stays available for at least N days" wording.
insert into zz_config (key, value, description) values
  ('card_link_days',        '90', 'Days a card link stays live after it is sent'),
  ('card_link_extend_days', '90', 'Days a card link is extended from the moment a real web view happens')
on conflict (key) do nothing;
