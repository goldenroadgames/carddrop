import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

// Shared by submit-reply (web replies), moderate-content (the iOS app's create
// steps) and send-card (the final gate before a card is stored). Calls OpenAI's
// moderation endpoint with the OPENAI_API_KEY secret, so no key lives in the
// app or the web page.
//
// Same rule the iOS app always used: a category blocks only when OpenAI flags
// it AND its score reaches our zz_config moderation_threshold_<category>
// (a category with no threshold row is blocked on OpenAI's own flag alone).
// Fails closed: if OpenAI can't be reached the verdict is "error".
export type ModerationVerdict =
  | { status: "clean" }
  | { status: "flagged"; categories: string[] }
  | { status: "error" };

// Human-readable names shown to the user (same labels the app used).
const LABELS: Record<string, string> = {
  "harassment": "harassment",
  "harassment/threatening": "threatening harassment",
  "hate": "hate speech",
  "hate/threatening": "threatening hate speech",
  "illicit": "illicit content",
  "illicit/violent": "violent illicit content",
  "self-harm": "self-harm",
  "self-harm/intent": "self-harm",
  "self-harm/instructions": "self-harm",
  "sexual": "sexually explicit content",
  "sexual/minors": "content involving minors",
  "violence": "violent content",
  "violence/graphic": "graphic violence",
};

type ModerationItem = {
  categories: Record<string, boolean>;
  category_scores: Record<string, number>;
};

export async function moderateContent(
  supabase: SupabaseClient,
  input: { texts?: string[]; images?: Uint8Array[] },
): Promise<ModerationVerdict> {
  // Duplicates are dropped (e.g. the message preview is part of the message).
  const texts = Array.from(new Set((input.texts ?? []).map((t) => t.trim()).filter((t) => t.length > 0)));
  const images = input.images ?? [];
  if (texts.length === 0 && images.length === 0) return { status: "clean" };

  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) {
    console.error("OPENAI_API_KEY is not set");
    return { status: "error" };
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
  // One call carries up to 25 texts, each scored separately (a longer list
  // is split into batches, so nothing is left unchecked).
  for (let i = 0; i < texts.length; i += 25) {
    bodies.push({ model: "omni-moderation-latest", input: texts.slice(i, i + 25) });
  }
  for (const image of images) {
    bodies.push({
      model: "omni-moderation-latest",
      input: [{ type: "image_url", image_url: { url: `data:image/jpeg;base64,${toBase64(image)}` } }],
    });
  }

  const results = await Promise.all(bodies.map((b) => callModeration(apiKey, b)));
  if (results.some((r) => r === null)) return { status: "error" };

  const flagged = new Set<string>();
  for (const items of results as ModerationItem[][]) {
    for (const item of items) {
      for (const [category, on] of Object.entries(item.categories ?? {})) {
        if (on && (item.category_scores?.[category] ?? 1) >= (thresholds[category] ?? 0)) {
          flagged.add(LABELS[category] ?? category);
        }
      }
    }
  }
  return flagged.size === 0
    ? { status: "clean" }
    : { status: "flagged", categories: Array.from(flagged).sort() };
}

async function callModeration(apiKey: string, body: unknown): Promise<ModerationItem[] | null> {
  // One retry on a rate limit (429), a server error (5xx), a timeout or a
  // network error; each try is cut off after 10 seconds so nothing hangs.
  const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const res = await fetch("https://api.openai.com/v1/moderations", {
        method: "POST",
        headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(10_000),
      });
      if ((res.status === 429 || res.status >= 500) && attempt === 0) {
        await sleep(res.status === 429 ? 3000 : 1000);
        continue;
      }
      if (!res.ok) {
        console.error("moderation HTTP", res.status);
        return null;
      }
      const json = await res.json();
      return Array.isArray(json.results) ? json.results : null;
    } catch (err) {
      if (attempt === 0) {
        await sleep(1000);
        continue;
      }
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
