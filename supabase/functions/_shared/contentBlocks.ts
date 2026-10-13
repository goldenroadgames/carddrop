import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

// Records a moderation block against the account and applies the strike rules.
// Called by moderate-content (the app's create steps), send-card and
// submit-to-lob.
//
// What counts: every blocked item, any category. Photos and text each have
// their own strike tiers. A check that flags both a photo and text writes two
// rows, one per kind, and each is counted against its own tier.
//
// Limits are in zz_config, one pair per kind:
//   content_block_limit_photo_24h / content_block_limit_photo_30d
//   content_block_limit_text_24h  / content_block_limit_text_30d
// A kind with no row of its own falls back to the older shared
// content_block_limit_24h / _30d, then to the defaults below. Reaching either
// limit of EITHER kind suspends the account and the device (same path as
// repeated recipient complaints: ban_account + user_devices.banned; the admin
// page can reinstate). Warnings start three blocks before a limit ("warn", also two before), but not before 2 strikes in that window, then
// one before ("final"), worked out per kind; the more severe one is returned.
export type BlockOutcome = { suspended: boolean; warning: "none" | "warn" | "final" };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DEFAULT_LIMIT_24H = 6;
const DEFAULT_LIMIT_30D = 15;
const MIN_STRIKES_FOR_WARNING = 2;

type Kind = "photo" | "text";

export async function recordContentBlock(
  supabase: SupabaseClient,
  input: {
    userId: string;
    deviceUUID?: string | null;
    parts: { kind: Kind; categories: string[]; fingerprints: string[]; scores: Record<string, number> }[];
  },
): Promise<BlockOutcome> {
  const none: BlockOutcome = { suspended: false, warning: "none" };
  try {
    if (input.parts.length === 0) return none;
    const deviceUUID = input.deviceUUID && UUID_RE.test(input.deviceUUID) ? input.deviceUUID : null;

    // A block only counts if at least one flagged item is NEW (not flagged for
    // this user in the last 24 hours). Tapping Next again, moving between
    // steps, the send-time re-check, or fixing one of several flagged items
    // and retrying with the rest unchanged are the same mistakes, not new
    // strikes: they are recorded but don't count.
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

    const rows = input.parts.map((part) => ({
      kind: part.kind,
      part,
      counted: part.fingerprints.length === 0 || part.fingerprints.some((f) => !seen.has(f)),
    }));

    const { error: insertError } = await supabase.from("content_blocks").insert(
      rows.map((r) => ({
        user_id: input.userId,
        device_uuid: deviceUUID,
        kind: r.kind,
        categories: r.part.categories,
        counted: r.counted,
        fingerprints: r.part.fingerprints,
        scores: r.part.scores,
      })),
    );
    if (insertError) {
      console.error("content_blocks insert error:", insertError.code, insertError.message);
      return none;
    }

    const { data: cfgRows } = await supabase
      .from("zz_config")
      .select("key, value")
      .like("key", "content_block_limit_%");
    const cfg: Record<string, number> = {};
    for (const r of cfgRows ?? []) cfg[r.key] = parseInt(r.value, 10);
    const pick = (...keys: string[]): number | null => {
      for (const k of keys) if (cfg[k] > 0) return cfg[k];
      return null;
    };
    const limitsFor = (kind: Kind) => ({
      limit24: pick(`content_block_limit_${kind}_24h`, "content_block_limit_24h") ?? DEFAULT_LIMIT_24H,
      limit30: pick(`content_block_limit_${kind}_30d`, "content_block_limit_30d") ?? DEFAULT_LIMIT_30D,
    });

    const count = async (kind: Kind, hours: number): Promise<number> => {
      const since = new Date(Date.now() - hours * 3600_000).toISOString();
      const { count: n } = await supabase
        .from("content_blocks")
        .select("id", { count: "exact", head: true })
        .eq("user_id", input.userId)
        .eq("kind", kind)
        .eq("counted", true)
        .gte("created_at", since);
      return n ?? 0;
    };

    let suspend = false;
    let warning: BlockOutcome["warning"] = "none";
    for (const r of rows) {
      const { limit24, limit30 } = limitsFor(r.kind);
      const [c24, c30] = await Promise.all([count(r.kind, 24), count(r.kind, 24 * 30)]);
      if (r.counted && (c24 >= limit24 || c30 >= limit30)) {
        suspend = true;
        continue;
      }
      // Each window warns on its own: 3 and 2 left = "warn", 1 left = "final",
      // but never before 2 strikes in that window, whatever its limit.
      for (const [used, limit] of [[c24, limit24], [c30, limit30]]) {
        if (used < MIN_STRIKES_FOR_WARNING) continue;
        const remaining = limit - used;
        const w = remaining === 1 ? "final" : remaining === 2 || remaining === 3 ? "warn" : "none";
        if (w === "final" || (w === "warn" && warning === "none")) warning = w;
      }
    }

    if (suspend) {
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

    return { suspended: false, warning };
  } catch (err) {
    console.error("recordContentBlock error:", err);
    return none;
  }
}
