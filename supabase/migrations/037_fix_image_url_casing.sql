-- cards.teaser_image_url / thumbnail_url were built (in send-card) from
-- Swift's UUID.uuidString, which is uppercase, while the actual storage
-- object path is lowercased (CardUploadService.swift uploads to
-- cardID.uuidString.lowercased()) — every existing row's stored URL is
-- broken (400s) against the real file. Every other segment of these URLs
-- (domain, bucket name, sender_id — already a lowercase Postgres uuid) is
-- already lowercase, so a blanket lower() is safe and fixes just the
-- cardID segment. The send-card edge function itself is fixed separately
-- (lowercases before building the URL) so new rows are written correctly
-- going forward — this migration only backfills existing rows.
update cards
set teaser_image_url = lower(teaser_image_url),
    thumbnail_url = lower(thumbnail_url)
where teaser_image_url is not null
   or thumbnail_url is not null;
