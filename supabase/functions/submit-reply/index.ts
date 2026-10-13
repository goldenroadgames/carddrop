import { createClient } from "jsr:@supabase/supabase-js@2";
import { checkCardAcceptsReplies } from "../_shared/replyGate.ts";
import { moderateContent } from "../_shared/moderation.ts";

// Called from the public card reply forms (anon key, no login).
// multipart/form-data: cardID, text. Replies are text only: a request that
// carries a photo is refused, because a web visitor can't be tied to who sent
// it. Order: validate -> per-IP rate limit -> card still live -> OpenAI
// moderation of the text -> insert the reply. If OpenAI can't be reached the
// reply is rejected (fail closed).
//
// Errors are {error: code}: invalid | unavailable | replies_off | rate_limited |
// rejected | try_later. The page maps each code to a visitor-facing message.
//
// Needs the OPENAI_API_KEY secret (supabase secrets set OPENAI_API_KEY=...).

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_TEXT_CHARS = 2000;
const DEFAULT_ATTEMPTS_PER_HOUR = 10;

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

    // ---------------- validate ----------------
    let form: FormData;
    try {
      form = await req.formData();
    } catch {
      return json({ error: "invalid" }, 400);
    }
    const cardID = String(form.get("cardID") ?? "").toLowerCase();
    const text = String(form.get("text") ?? "").trim().slice(0, MAX_TEXT_CHARS);
    // No photos: refuse any request that carries one.
    if (form.get("photo") !== null) return json({ error: "invalid" }, 400);
    if (!UUID_RE.test(cardID) || !text) return json({ error: "invalid" }, 400);

    // ---------------- per-IP rate limit ----------------
    const ipHash = await hashIp(req);
    const limit = await attemptsPerHour(supabase);
    const since = new Date(Date.now() - 3600_000).toISOString();
    const { count, error: countError } = await supabase
      .from("reply_attempts")
      .select("id", { count: "exact", head: true })
      .eq("ip_hash", ipHash)
      .gte("created_at", since);
    if (countError) {
      console.error("reply_attempts count error:", countError);
      return json({ error: "try_later" }, 503);
    }
    if ((count ?? 0) >= limit) return json({ error: "rate_limited" }, 429);
    // Every attempt counts, including ones moderation rejects.
    await supabase.from("reply_attempts").insert({ ip_hash: ipHash });
    if (Math.random() < 0.02) {
      await supabase
        .from("reply_attempts")
        .delete()
        .lt("created_at", new Date(Date.now() - 2 * 86400000).toISOString());
    }

    // ---------------- card still live, replies allowed? ----------------
    // Not deleted / reported / suspended sender, and the sender hasn't switched
    // replies off (card or profile). Checked before moderation so nothing is
    // processed or stored for a card that isn't accepting replies.
    const gate = await checkCardAcceptsReplies(supabase, cardID);
    if (!gate.ok) return json({ error: gate.error }, gate.error === "replies_off" ? 403 : 404);
    const card = gate.card;

    // ---------------- moderation (fail closed) ----------------
    const verdict = await moderateContent(supabase, { texts: [text] });
    if (verdict.status === "error") return json({ error: "try_later" }, 503);
    if (verdict.status === "flagged") return json({ error: "rejected" }, 422);

    // ---------------- insert reply ----------------
    const { error: insertError } = await supabase.from("replies").insert({
      card_id: card.id,
      reply_text: text,
    });
    if (insertError) {
      console.error("reply insert error:", insertError.code, insertError.message);
      return json({ error: "try_later" }, 500);
    }

    return json({ status: "ok" });
  } catch (err) {
    console.error("submit-reply error:", err);
    return json({ error: "try_later" }, 500);
  }
});

// ---------------------------------------------------------------------------

// Keyed hash of the visitor's IP, so the table never holds a raw address.
// cf-connecting-ip is set by Cloudflare in front of Supabase and can't be
// forged by the caller; the other headers are fallbacks.
async function hashIp(req: Request): Promise<string> {
  const ip = req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-real-ip") ??
    req.headers.get("x-forwarded-for")?.split(",")[0].trim() ??
    "unknown";
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(ip)));
  return Array.from(sig, (b) => b.toString(16).padStart(2, "0")).join("");
}

// deno-lint-ignore no-explicit-any
async function attemptsPerHour(supabase: any): Promise<number> {
  const { data } = await supabase
    .from("zz_config")
    .select("value")
    .eq("key", "reply_attempts_per_ip_hourly")
    .maybeSingle();
  const n = parseInt(data?.value ?? "", 10);
  return n > 0 ? n : DEFAULT_ATTEMPTS_PER_HOUR;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
