-- Marketing use of card designs becomes OPT-IN (Privacy Policy Section 5).
--
-- 1. New accounts start with allow_marketing_use = false (was true). They are
--    asked to opt in (Settings toggle now; first-send prompt later).
-- 2. Existing REGISTERED accounts are deliberately left as they are.
-- 3. Anonymous accounts must never be eligible: set them to false. They have
--    no way to consent or be contacted, and the toggle is hidden for them.
--    (auth.users.is_anonymous identifies them.)

alter table users
  alter column allow_marketing_use set default false;

update users u
set allow_marketing_use = false
from auth.users a
where a.id = u.id
  and a.is_anonymous = true
  and u.allow_marketing_use = true;
