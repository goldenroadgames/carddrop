-- Replies are text only from now on: a web visitor can't be tied to who sent a
-- photo. submit-reply refuses photos, the web forms and the iOS app no longer
-- show them.
--
-- Run AFTER deploying submit-reply, delete-reply and the functions that share
-- purgeCard.ts / clearReplies.ts, and pushing web. Then delete the
-- reply-photos storage bucket from the Supabase dashboard (empty it first).
-- Do NOT drop the bucket with SQL.
--
-- 1. Replies that were only a photo have nothing left to show: delete them.
-- 2. Clear the photo address from the rest.
-- The reply_image_url column stays (nullable, always empty from now on): older
-- app builds still select it, and a missing column would break their reply list.
delete from replies where reply_image_url is not null and (reply_text is null or btrim(reply_text) = '');
update replies set reply_image_url = null where reply_image_url is not null;
