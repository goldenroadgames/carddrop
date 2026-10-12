-- Report form question "Does this card show or involve a child?" (yes / no /
-- not sure). Stored on the complaint row; null = reported before the question
-- existed. Run BEFORE redeploying submit-complaint.
alter table card_complaints
  add column if not exists involves_minor text
  check (involves_minor in ('yes', 'no', 'not_sure'));
