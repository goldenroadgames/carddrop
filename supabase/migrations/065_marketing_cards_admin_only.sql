-- 036 let ANY authenticated user (including anonymous sign-ins) insert or
-- update ANY object in the marketing-cards bucket, so anyone with the anon
-- key could overwrite marketing images. The only legitimate writers are the
-- webapp admin pages (service-role key) and manual Supabase CLI/dashboard
-- work, and both bypass RLS. The iOS app only reads, via public URLs.
-- With RLS on and no write policy, only the service role can write.
-- "marketing-cards: public read" is untouched.

drop policy if exists "marketing-cards: auth users can upload" on storage.objects;
drop policy if exists "marketing-cards: auth users can update" on storage.objects;
