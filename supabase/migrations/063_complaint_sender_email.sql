-- Keep the reported sender's email for 12 months, even if they delete their
-- account (the sign-in record, and its email, are removed at deletion).
-- Written by submit-complaint when the report is filed; blanked with the
-- complaint text by the sweeper at 12 months. Null for anonymous senders.
alter table card_complaints add column if not exists sender_email text;
