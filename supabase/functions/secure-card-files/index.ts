import { createClient } from "jsr:@supabase/supabase-js@2";
import { syncCardFiles } from "../_shared/cardFiles.ts";

// Moves one card's image files between the public and private buckets to match
// its state (private while reported or on legal hold, public otherwise). Called
// by the admin web app's server code, which sends the SERVICE ROLE key; nothing
// else may call it. Body: { cardID }. Reply: { ok: true } or { ok: false, error }.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  try {
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const given = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    if (!given || given !== serviceKey) return json({ ok: false, error: "unauthorized" }, 401);

    const { cardID } = await req.json().catch(() => ({}));
    if (typeof cardID !== "string" || !UUID_RE.test(cardID)) return json({ ok: false, error: "cardID required" }, 400);

    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey);
    const err = await syncCardFiles(supabase, cardID.toLowerCase());
    if (err) {
      console.error("secure-card-files error:", cardID, err);
      return json({ ok: false, error: err }, 500);
    }
    return json({ ok: true });
  } catch (e) {
    console.error("secure-card-files error:", e);
    return json({ ok: false, error: "Internal server error" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
