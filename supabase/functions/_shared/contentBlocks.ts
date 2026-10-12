import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

// Records a moderation block against the account and applies the strike rules.
// Called by moderate-content (the app's create steps) and send-card.
//
// What counts: any blocked PHOTO, and any HARASSMENT flag (text or photo).
// Other blocked language (violence, rude words...) is recorded but doesn't
// count, so people can clean it up and carry on.
//
// Limits are in zz_config: content_block_limit_24h (default 6) and
// content_block_limit_30d (default 15). Reaching either suspends the account
// and the device (same path as repeated recipient complaints: ban_account +
// user_devices.banned; the admin page can reinstate). Warnings start two
// blocks before a limit ("warn"), then one before ("final").
export type BlockOutcome = { suspended: boolean; warning: "none" | "warn" | "final" };

const HARASSMENT = new Set(["harassment", "threatening harassment"]);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DEFAULT_LIMIT_24H = 6;
const DEFAULT_LIMIT_30D = 15;

export async function recordContentBlock(
  supabase: SupabaseClient,
  input: {
    userId: string;
    deviceUUID?: string | null;
    photo: boolean;
    text: boolean;
    categories: string[];
    fingerprints: string[];
    scores: Record<string, number>;
  },
): Promise<BlockOutcome> {
  const none: BlockOutcome = { suspended: false, warning: "none" };
  try {
    const countable = input.photo || (input.text && input.categories.some((c) => HARASSMENT.has(c)));
    const deviceUUID = input.deviceUUID && UUID_RE.test(input.deviceUUID) ? input.deviceUUID : null;

    // A block only counts if at least one flagged item is NEW (not flagged for
    // this user in the last 24 hours). Tapping Next again, moving between
    // steps, the send-time re-check, or fixing one of several flagged items
    // and retrying with the rest unchanged are the same mistakes, not new
    // strikes: they are recorded but don't count.
    let hasNewItem = true;
    if (countable) {
      const since24 = new Date(Date.now() - 24 * 3600_000).toISOString();
      const { data: priorRows } = await supabase
        .from("content_blocks")
        .select("fingerprints")
        .eq("user_id", input.userId)
        .gte("created_at", since24);
      const seen = new Set<string>();
      for (const row of priorRows ?? []) {
        for (const f of (row.fingerprints ?? []) as string[]) seen.add(f);
      }
      hasNewItem = input.fingerprints.length === 0 || input.fingerprints.some((f) => !seen.has(f));
    }
    const counted = countable && hasNewItem;

    const { error: insertError } = await supabase.from("content_blocks").insert({
      user_id: input.userId,
      device_uuid: deviceUUID,
      kind: input.photo ? "photo" : "text",
      categories: input.categories,
      counted,
      fingerprints: input.fingerprints,
      scores: input.scores,
    });
    if (insertError) {
      console.error("content_blocks insert error:", insertError.code, insertError.message);
      return none;
    }
    if (!countable) return none;

    const { data: cfgRows } = await supabase
      .from("zz_config")
      .select("key, value")
      .in("key", ["content_block_limit_24h", "content_block_limit_30d"]);
    const cfg: Record<string, number> = {};
    for (const r of cfgRows ?? []) cfg[r.key] = parseInt(r.value, 10);
    const limit24 = cfg["content_block_limit_24h"] > 0 ? cfg["content_block_limit_24h"] : DEFAULT_LIMIT_24H;
    const limit30 = cfg["content_block_limit_30d"] > 0 ? cfg["content_block_limit_30d"] : DEFAULT_LIMIT_30D;

    const count = async (hours: number): Promise<number> => {
      const since = new Date(Date.now() - hours * 3600_000).toISOString();
      const { count: n } = await supabase
        .from("content_blocks")
        .select("id", { count: "exact", head: true })
        .eq("user_id", input.userId)
        .eq("counted", true)
        .gte("created_at", since);
      return n ?? 0;
    };
    const [c24, c30] = await Promise.all([count(24), count(24 * 30)]);

    if (counted && (c24 >= limit24 || c30 >= limit30)) {
      await supabase.rpc("ban_account", {
        p_user_id: input.userId,
        p_reason: "repeated blocked content",
      });
      if (deviceUUID) {
        await supabase.from("user_devices").upsert(
          {
            device_uuid: deviceUUID,
            banned: true,
            banned_at: new Date().toISOString(),
            ban_reason: "repeated blocked content",
          },
          { onConflict: "device_uuid" },
        );
      }
      return { suspended: true, warning: "none" };
    }

    const remaining = Math.min(limit24 - c24, limit30 - c30);
    return { suspended: false, warning: remaining === 1 ? "final" : remaining === 2 ? "warn" : "none" };
  } catch (err) {
    console.error("recordContentBlock error:", err);
    return none;
  }
}
