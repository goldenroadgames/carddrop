-- Sender controls for replies and emoji reactions (see replies_control_plan.md).
--   users.replies_enabled : profile switch, replies + reactions off for ALL cards
--   cards.replies_enabled : per-card switch (set from the sent-card page)
-- Both default to true, so every card accepts replies unless the sender turns
-- them off. Profile-off overrides the card switch. The app does not write
-- these columns directly: the set-replies-enabled edge function (service
-- role) does, so no client grant is needed. Enforced server-side by
-- submit-reply and submit-reaction; the web card page also hides the UI.
alter table users add column if not exists replies_enabled boolean not null default true;
alter table cards add column if not exists replies_enabled boolean not null default true;
