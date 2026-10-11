import { createClient } from "jsr:@supabase/supabase-js@2";
import { checkCardAcceptsReplies } from "../_shared/replyGate.ts";

// Called from the public card reply forms (anon key, no login).
// multipart/form-data: cardID, text (optional), photo (optional JPEG, already
// resized by the page). Order: validate -> per-IP rate limit -> card still
// live -> OpenAI moderation of text and photo -> store the photo -> insert the
// reply. If OpenAI can't be reached the reply is rejected (fail closed).
// The photo is only written to storage after it passes moderation.
//
// Errors are {error: code}: invalid | unavailable | replies_off | rate_limited |
// rejected | try_later. The page maps each code to a visitor-facing message.
//
// Needs the OPENAI_API_KEY secret (supabase secrets set OPENAI_API_KEY=...).

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_PHOTO_BYTES = 5 * 1024 * 1024;
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
    const photoField = form.get("photo");
    const photo = photoField instanceof File && photoField.size > 0 ? photoField : null;
    if (!UUID_RE.test(cardID) || (!text && !photo)) return json({ error: "invalid" }, 400);

    let photoBytes: Uint8Array | null = null;
    if (photo) {
      if (photo.size > MAX_PHOTO_BYTES) return json({ error: "invalid" }, 400);
      photoBytes = new Uint8Array(await photo.arrayBuffer());
      // JPEG magic bytes (FF D8 FF): the page always sends a re-encoded JPEG.
      if (photoBytes[0] !== 0xff || photoBytes[1] !== 0xd8 || photoBytes[2] !== 0xff) {
        return json({ error: "invalid" }, 400);
      }
    }

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
    const verdict = await moderate(supabase, text, photoBytes);
    if (verdict === "error") return json({ error: "try_later" }, 503);
    if (verdict === "flagged") return json({ error: "rejected" }, 422);

    // ---------------- store photo, insert reply ----------------
    let imageUrl: string | null = null;
    let uploadedPath: string | null = null;
    if (photoBytes) {
      uploadedPath = `${card.id}/${Date.now()}-${crypto.randomUUID().slice(0, 8)}.jpg`;
      const { error: uploadError } = await supabase.storage
        .from("reply-photos")
        .upload(uploadedPath, photoBytes, { contentType: "image/jpeg" });
      if (uploadError) {
        console.error("reply photo upload error:", uploadError);
        return json({ error: "try_later" }, 500);
      }
      imageUrl = supabase.storage.from("reply-photos").getPublicUrl(uploadedPath).data.publicUrl;
    }

    const { error: insertError } = await supabase.from("replies").insert({
      card_id: card.id,
      reply_text: text || null,
      reply_image_url: imageUrl,
    });
    if (insertError) {
      console.error("reply insert error:", insertError);
      if (uploadedPath) await supabase.storage.from("reply-photos").remove([uploadedPath]);
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

type ModerationItem = {
  categories: Record<string, boolean>;
  category_scores: Record<string, number>;
};

// Same rule as the iOS ModerationService: a category blocks only when OpenAI
// flags it AND its score reaches our zz_config moderation_threshold_<category>
// (no threshold row = OpenAI's own flag alone blocks).
// deno-lint-ignore no-explicit-any
async function moderate(supabase: any, text: string, photo: Uint8Array | null): Promise<"clean" | "flagged" | "error"> {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    console.error("OPENAI_API_KEY is not set");
    return "error";
  }

  const { data: rows } = await supabase
    .from("zz_config")
    .select("key, value")
    .like("key", "moderation_threshold_%");
  const thresholds: Record<string, number> = {};
  for (const r of rows ?? []) {
    const score = Number(r.value);
    if (!Number.isNaN(score)) thresholds[r.key.replace("moderation_threshold_", "")] = score;
  }

  const bodies: unknown[] = [];
  if (text) bodies.push({ model: "omni-moderation-latest", input: [text] });
  if (photo) {
    bodies.push({
      model: "omni-moderation-latest",
      input: [{ type: "image_url", image_url: { url: `data:image/jpeg;base64,${toBase64(photo)}` } }],
    });
  }

  const results = await Promise.all(bodies.map((b) => callModeration(apiKey, b)));
  if (results.some((r) => r === null)) return "error";

  for (const items of results as ModerationItem[][]) {
    for (const item of items) {
      for (const [category, on] of Object.entries(item.categories ?? {})) {
        if (on && (item.category_scores?.[category] ?? 1) >= (thresholds[category] ?? 0)) {
          return "flagged";
        }
      }
    }
  }
  return "clean";
}

async function callModeration(apiKey: string, body: unknown): Promise<ModerationItem[] | null> {
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const res = await fetch("https://api.openai.com/v1/moderations", {
        method: "POST",
        headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      if (res.status === 429 && attempt === 0) {
        await new Promise((r) => setTimeout(r, 3000));
        continue;
      }
      if (!res.ok) {
        console.error("moderation HTTP", res.status);
        return null;
      }
      const json = await res.json();
      return Array.isArray(json.results) ? json.results : null;
    } catch (err) {
      console.error("moderation request failed:", err);
      return null;
    }
  }
  return null;
}

function toBase64(bytes: Uint8Array): string {
  let s = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    s += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(s);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}
