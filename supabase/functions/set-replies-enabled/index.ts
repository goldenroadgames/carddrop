import { createClient } from "jsr:@supabase/supabase-js@2";
import { clearReplies } from "../_shared/clearReplies.ts";

// Turns replies + emoji reactions on or off for ONE card (cardID given) or for
// the caller's whole account (no cardID; the profile switch overrides every
// card). Body: { enabled: boolean, cardID?: string, deleteExisting?: boolean }.
// deleteExisting only applies when turning replies off: it permanently removes
// the existing replies, photos and reactions (otherwise they are just not
// shown in the app, and reappear when switched back on). Reported cards are
// kept as evidence and are never cleared.
// The switch is written first, so new replies stop before old ones are deleted.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "unauthorized" }, 401);
    const jwt = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(jwt);
    if (authError || !user) return json({ error: "unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    if (typeof body.enabled !== "boolean") return json({ error: "enabled required" }, 400);
    const enabled: boolean = body.enabled;
    const deleteExisting = body.deleteExisting === true && !enabled;
    const cardID = typeof body.cardID === "string" ? body.cardID.toLowerCase() : null;
    if (body.cardID !== undefined && body.cardID !== null && (!cardID || !UUID_RE.test(cardID))) {
      return json({ error: "invalid cardID" }, 400);
    }

    if (cardID) {
      // ---- one card ----
      const { data: card } = await supabase
        .from("cards")
        .select("id, sender_id, reported_at, legal_hold")
        .eq("id", cardID)
        .maybeSingle();
      if (!card) return json({ status: "not_found" });
      if (card.sender_id !== user.id) return json({ error: "unauthorized" }, 403);

      const { error } = await supabase
        .from("cards")
        .update({ replies_enabled: enabled })
        .eq("id", card.id);
      if (error) {
        console.error("set-replies-enabled card update error:", error);
        return json({ error: "update_failed" }, 500);
      }
      if (deleteExisting && !card.reported_at && !card.legal_hold) {
        const clearError = await clearReplies(supabase, [card.id]);
        if (clearError) {
          console.error("set-replies-enabled clear error:", clearError);
          return json({ error: "clear_failed" }, 500);
        }
      }
      return json({ status: "ok" });
    }

    // ---- whole account ----
    const { error } = await supabase
      .from("users")
      .upsert({ id: user.id, replies_enabled: enabled }, { onConflict: "id" });
    if (error) {
      console.error("set-replies-enabled user update error:", error);
      return json({ error: "update_failed" }, 500);
    }

    if (deleteExisting) {
      const ids: string[] = [];
      for (let from = 0; ; from += 1000) {
        const { data, error: listError } = await supabase
          .from("cards")
          .select("id")
          .eq("sender_id", user.id)
          .is("reported_at", null)
          .eq("legal_hold", false)
          .range(from, from + 999);
        if (listError) {
          console.error("set-replies-enabled list error:", listError);
          return json({ error: "clear_failed" }, 500);
        }
        ids.push(...(data ?? []).map((c: { id: string }) => c.id));
        if (!data || data.length < 1000) break;
      }
      const clearError = await clearReplies(supabase, ids);
      if (clearError) {
        console.error("set-replies-enabled clear error:", clearError);
        return json({ error: "clear_failed" }, 500);
      }
    }
    return json({ status: "ok" });
  } catch (err) {
    console.error("set-replies-enabled error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
