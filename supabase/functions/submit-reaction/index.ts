import { createClient } from "jsr:@supabase/supabase-js@2";
import { checkCardAcceptsReplies } from "../_shared/replyGate.ts";

// Called from the public card page (anon key, no login) when a visitor taps an
// emoji. Replaces the old direct insert into reactions so the sender's
// "replies off" switch (card or profile) can be enforced. Body:
// { cardID, emoji }. Errors: {error: invalid | unavailable | replies_off |
// try_later}. No rate limit yet (the old direct insert had none either).
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Keep in sync with REACTIONS in web/app/card/[id]/CardView.tsx. Compared with
// the variation selector (U+FE0F) removed, since keyboards differ on it.
const ALLOWED = [
  "❤", // red heart
  "\u{1F642}",
  "\u{1F602}",
  "\u{1F60D}",
  "\u{1F979}",
  "\u{1F61C}",
  "\u{1F92D}",
  "\u{1F64F}\u{1F3FC}", // folded hands, medium-light skin tone
];
const strip = (s: string) => s.replace(/️/g, "");

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
    const emoji = typeof body.emoji === "string" ? body.emoji : "";
    if (!UUID_RE.test(cardID) || !ALLOWED.includes(strip(emoji))) {
      return json({ error: "invalid" }, 400);
    }

    const gate = await checkCardAcceptsReplies(supabase, cardID);
    if (!gate.ok) return json({ error: gate.error }, gate.error === "replies_off" ? 403 : 404);

    const { error } = await supabase.from("reactions").insert({ card_id: gate.card.id, emoji });
    if (error) {
      console.error("reaction insert error:", error);
      return json({ error: "try_later" }, 500);
    }
    return json({ status: "ok" });
  } catch (err) {
    console.error("submit-reaction error:", err);
    return json({ error: "try_later" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
