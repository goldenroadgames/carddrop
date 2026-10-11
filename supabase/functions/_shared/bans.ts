import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

// True if this caller is banned. A ban matches on ANY of:
//   - the account (account_bans.user_id)
//   - the account's VERIFIED email (account_bans.email; an unverified email
//     proves nothing, so it is never matched)
//   - the device (user_devices.banned) or any device already linked to the
//     account
// A banned device also flags the account it is signing in as, so the ban
// follows them if they switch devices. A ban is active while reinstated_at is null.
export async function isBanned(
  supabase: SupabaseClient,
  user: { id: string; email?: string | null },
  isVerified: boolean,
  deviceUUID?: string,
): Promise<boolean> {
  const { data: accountBan } = await supabase
    .from("account_bans")
    .select("id")
    .eq("user_id", user.id)
    .is("reinstated_at", null)
    .maybeSingle();
  if (accountBan) return true;

  if (isVerified && user.email) {
    const { data: emailBan } = await supabase
      .from("account_bans")
      .select("id")
      .eq("email", user.email.toLowerCase())
      .is("reinstated_at", null)
      .limit(1)
      .maybeSingle();
    if (emailBan) return true;
  }

  let deviceBanned = false;
  if (deviceUUID) {
    const { data: deviceRow } = await supabase
      .from("user_devices")
      .select("banned")
      .eq("device_uuid", deviceUUID)
      .maybeSingle();
    deviceBanned = deviceRow?.banned === true;
  }
  if (!deviceBanned) {
    const { data: linked } = await supabase
      .from("user_devices")
      .select("device_uuid")
      .eq("user_id", user.id)
      .eq("banned", true)
      .limit(1)
      .maybeSingle();
    deviceBanned = !!linked;
  }

  if (deviceBanned) {
    // Flag the account too (ban_account ignores a duplicate active ban).
    await supabase.rpc("ban_account", { p_user_id: user.id, p_reason: "device banned" });
    return true;
  }
  return false;
}
