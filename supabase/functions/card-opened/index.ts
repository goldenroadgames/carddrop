import { createClient } from "jsr:@supabase/supabase-js@2";
import { checkCardAcceptsReplies } from "../_shared/replyGate.ts";
import { sendPush } from "../_shared/push.ts";

// Called from the public card page (anon key) when a visitor really views a
// card: the first flip, a tap or scroll, or 20 seconds of visible time. A link
// preview or scanner that only fetches the HTML never runs the page, so it
// never calls this. Sets cards.first_opened_at the first time only; the sender's
// app shows it as the "opened" eyeball, and the sender gets ONE "Your card was
// opened" push (only the call that actually sets the column sends it).
// Body: { cardID }. Always answers {status:"ok"} for a well-formed request.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "invalid" }, 405);
  try {
    // Headless browsers (many scanners) announce themselves; ignore them.
    if (/headless/i.test(req.headers.get("user-agent") ?? "")) return json({ status: "ok" });

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

    // First call wins; repeats and concurrent calls change nothing.
    const { data: claimed, error } = await supabase
      .from("cards")
      .update({ first_opened_at: new Date().toISOString() })
      .eq("id", cardID)
      .is("first_opened_at", null)
      .select("id, sender_id");
    if (error) console.error("card-opened update error:", error.message);
    if (claimed && claimed.length > 0) await sendPush(supabase, claimed[0].sender_id, claimed[0].id, "opened");

    return json({ status: "ok" });
  } catch (err) {
    console.error("card-opened error:", err);
    return json({ status: "ok" });
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
