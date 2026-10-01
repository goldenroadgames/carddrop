-- Adds 'authorized' between pending_payment and paid, for manual-capture
-- Stripe PaymentIntents (see create-postcard-payment-intent). The card is
-- only ever authorized (funds held, not charged) at confirm-postcard-payment
-- time; submit-to-lob captures the hold on LOB success, or cancels it on
-- LOB failure — so a rejected postcard never actually charges the customer.

alter table physical_orders drop constraint physical_orders_status_check;
alter table physical_orders add constraint physical_orders_status_check
  check (status in (
    'pending_payment', 'authorized', 'paid', 'submitted_to_lob',
    'printed', 'mailed', 'delivered', 'failed', 'refunded'
  ));
