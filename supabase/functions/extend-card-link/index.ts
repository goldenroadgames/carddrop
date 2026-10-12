import { createClient } from "jsr:@supabase/supabase-js@2";
import { checkCardAcceptsReplies } from "../_shared/replyGate.ts";

// Called from the public card page (anon key) when a real browser views a card.
// Pushes the card's expiry out to now + card_link_extend_days (zz_config,
// default 90), with no cap, so a card people keep opening keeps living.
// Only a card that is live (not deleted, reported, or from a suspended sender)
// and not already expired is extended; an expired card is never revived here
// (the page doesn't render it, so no view happens). A card with no expiry is left
// alone. To avoid a database write on every view, nothing is written while the
// expiry is already more than (extend days - 1 day) away.
// Body: { cardID }. Always answers {status:"ok"} for a well-formed request.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DEFAULT_EXTEND_DAYS = 90;
const DAY_MS = 24 * 60 * 60 * 1000;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "invalid" }, 405);
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );

    const body = await req.json().catch(() => ({}));
    const cardID = typeof body.cardID === "string" ? body.cardID.toLowerCase() : "";
    if (!UUID_RE.test(cardID)) return json({ error: "invalid" }, 400);

    // Live = not deleted / reported / suspended. "replies_off" is still live.
    const gate = await checkCardAcceptsReplies(supabase, cardID);
    if (!gate.ok && gate.error === "unavailable") return json({ status: "ok" });

    const { data: card } = await supabase
      .from("cards")
      .select("expires_at")
      .eq("id", cardID)
      .maybeSingle();
    if (!card || !card.expires_at) return json({ status: "ok" });

    const now = Date.now();
    const expiresAt = new Date(card.expires_at).getTime();
    if (expiresAt <= now) return json({ status: "ok" }); // expired: never revived here

    const { data: cfg } = await supabase
      .from("zz_config")
      .select("value")
      .eq("key", "card_link_extend_days")
      .maybeSingle();
    const parsed = parseInt(cfg?.value ?? "", 10);
    const extendDays = parsed > 0 ? parsed : DEFAULT_EXTEND_DAYS;

    const target = now + extendDays * DAY_MS;
    if (expiresAt >= target - DAY_MS) return json({ status: "ok" }); // already far enough out

    const { error } = await supabase
      .from("cards")
      .update({ expires_at: new Date(target).toISOString() })
      .eq("id", cardID);
    if (error) console.error("extend-card-link update error:", error);
    return json({ status: "ok" });
  } catch (err) {
    console.error("extend-card-link error:", err);
    return json({ status: "ok" });
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
