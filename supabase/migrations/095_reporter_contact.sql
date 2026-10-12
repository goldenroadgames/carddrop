-- Optional contact (email or phone) a reporter can leave when they answer YES
-- or NOT SURE to "does this card show or involve a child?", so we can reach
-- them if the card is gone and their copy is the only evidence. Kept with the
-- complaint for retention_days (the sweeper clears it with the complaint text).
-- Run before redeploying submit-complaint.
alter table card_complaints add column if not exists reporter_contact text;
