-- Step 5 of carddrop/card_delete_complaints_bans_plan.md: account deletion.
-- Run AFTER 056.
--
-- Deleting an account must not be blocked by (or wipe) the records we keep on
-- purpose: card tombstones (so recipients can still report an old card),
-- order records (payment audit), and promo redemptions. So these columns stop
-- being enforced foreign keys; the uuid they hold becomes a plain identifier
-- that no longer points at anyone once the account is gone.

alter table cards drop constraint if exists cards_sender_id_fkey;

alter table physical_orders drop constraint if exists physical_orders_sender_id_fkey;
alter table physical_orders alter column sender_id drop not null;

alter table promo_code_redemptions drop constraint if exists promo_code_redemptions_user_id_fkey;
