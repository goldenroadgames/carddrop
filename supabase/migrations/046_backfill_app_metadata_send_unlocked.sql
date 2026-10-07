-- send_unlocked now lives in app_metadata (server-written only, set by the
-- verify-email-otp Edge Function) instead of user_metadata, which any
-- signed-in user can write to themselves. Carry the flag over for accounts
-- that already have it. Run this BEFORE deploying the functions and the app.
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"send_unlocked": true}'::jsonb
where raw_user_meta_data->>'send_unlocked' = 'true';
