import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

// Monthly per-user stats (user_send_stats, migration 120). Best effort: a
// failure is logged and never changes the caller's response.
export async function bumpSendStat(
  supabase: SupabaseClient,
  userId: string,
  field: "digital_sends" | "mail_orders" | "rate_cap_hits",
): Promise<void> {
  try {
    const { error } = await supabase.rpc("bump_user_send_stat", { p_user_id: userId, p_field: field });
    if (error) console.error("user_send_stats error:", field, error.message);
  } catch (err) {
    console.error("user_send_stats error:", field, err);
  }
}
