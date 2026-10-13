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
  // photo / text say which kind of input was flagged.
  // fingerprints = one-way hash of EACH flagged text/photo, so the same flagged
  // item tried again can be counted once even if other items on the card change
  // (contentBlocks.ts).
  // scores = highest OpenAI score (0-1) per flagged category label, kept with
  // the block record so a borderline flag can be told from a clear one.
  // parts = the same flags split by kind (one entry for photos if any photo was
  // flagged, one for text if any text was flagged). Every flagged block counts
  // as a strike, photos and text each against their own limits (contentBlocks.ts).
  // textFlags = each flagged (trimmed) text string with its own categories, so the
  // app can say which field was flagged (moderate-content).
  | { status: "flagged"; categories: string[]; photo: boolean; text: boolean; fingerprints: string[]; scores: Record<string, number>; parts: BlockPart[]; textFlags: { text: string; categories: string[] }[] }
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

export type BlockPart = {
  kind: "photo" | "text";
  categories: string[];
  fingerprints: string[];
  scores: Record<string, number>;
  // photo parts only: the storage keys of the flagged staged images (not set
  // for images passed as bytes), so the app can say which image it was.
  imageKeys?: string[];
};

type ModerationItem = {
  categories: Record<string, boolean>;
  category_scores: Record<string, number>;
};

export async function moderateContent(
  supabase: SupabaseClient,
  // imageUrls: images OpenAI fetches itself (e.g. short-lived signed URLs of
  // private staged files), so large files never pass through this function.
  // key = a stable string for the file (its storage path), hashed as the
  // fingerprint instead of the bytes.
  input: { texts?: string[]; images?: Uint8Array[]; imageUrls?: { url: string; key: string }[] },
): Promise<ModerationVerdict> {
  // Duplicates are dropped (e.g. the message preview is part of the message).
  const texts = Array.from(new Set((input.texts ?? []).map((t) => t.trim()).filter((t) => t.length > 0)));
  const images = input.images ?? [];
  const imageUrls = input.imageUrls ?? [];
  if (texts.length === 0 && images.length === 0 && imageUrls.length === 0) return { status: "clean" };

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

  const calls: { kind: "text" | "photo"; body: unknown; inputs: string[]; image?: Uint8Array; key?: string }[] = [];
  // One call carries up to 25 texts, each scored separately (a longer list
  // is split into batches, so nothing is left unchecked).
  for (let i = 0; i < texts.length; i += 25) {
    const batch = texts.slice(i, i + 25);
    calls.push({ kind: "text", body: { model: "omni-moderation-latest", input: batch }, inputs: batch });
  }
  for (const image of images) {
    calls.push({
      kind: "photo",
      inputs: [],
      image,
      body: {
        model: "omni-moderation-latest",
        input: [{ type: "image_url", image_url: { url: `data:image/jpeg;base64,${toBase64(image)}` } }],
      },
    });
  }

  for (const { url, key } of imageUrls) {
    calls.push({
      kind: "photo",
      inputs: [],
      key,
      image: new TextEncoder().encode(key),
      body: {
        model: "omni-moderation-latest",
        input: [{ type: "image_url", image_url: { url } }],
      },
    });
  }

  const results = await Promise.all(
    calls.map(async (c) => ({ call: c, items: await callModeration(apiKey, c.body) })),
  );
  if (results.some((r) => r.items === null)) return { status: "error" };

  const flagged = new Set<string>();
  const scores: Record<string, number> = {};
  const kindCategories = { photo: new Set<string>(), text: new Set<string>() };
  const kindScores: { photo: Record<string, number>; text: Record<string, number> } = { photo: {}, text: {} };
  const flaggedTexts = new Set<string>();
  const flaggedImages: Uint8Array[] = [];
  const flaggedKeys = new Set<string>();
  const textFlagMap = new Map<string, Set<string>>();
  let photoFlagged = false;
  let textFlagged = false;
  for (const r of results) {
    const items = r.items as ModerationItem[];
    // OpenAI returns one result per input string, in order. If that ever
    // doesn't hold, a flagged result can't be tied to one string, so the whole
    // batch is treated as the flagged item (conservative, never skips a check).
    const aligned = r.call.kind === "photo" || items.length === r.call.inputs.length;
    items.forEach((item, idx) => {
      let itemFlagged = false;
      const itemLabels = new Set<string>();
      for (const [category, on] of Object.entries(item.categories ?? {})) {
        if (on && (item.category_scores?.[category] ?? 1) >= (thresholds[category] ?? 0)) {
          const label = LABELS[category] ?? category;
          flagged.add(label);
          const rounded = Math.round((item.category_scores?.[category] ?? 0) * 1000) / 1000;
          scores[label] = Math.max(scores[label] ?? 0, rounded);
          itemLabels.add(label);
          kindCategories[r.call.kind].add(label);
          kindScores[r.call.kind][label] = Math.max(kindScores[r.call.kind][label] ?? 0, rounded);
          itemFlagged = true;
        }
      }
      if (!itemFlagged) return;
      if (r.call.kind === "photo") {
        photoFlagged = true;
        if (r.call.image) flaggedImages.push(r.call.image);
        if (r.call.key) flaggedKeys.add(r.call.key);
      } else {
        textFlagged = true;
        const flaggedHere = aligned ? (r.call.inputs[idx] !== undefined ? [r.call.inputs[idx]] : []) : r.call.inputs;
        for (const t of flaggedHere) {
          flaggedTexts.add(t);
          const set = textFlagMap.get(t) ?? new Set<string>();
          itemLabels.forEach((l) => set.add(l));
          textFlagMap.set(t, set);
        }
      }
    });
  }
  if (flagged.size === 0) return { status: "clean" };

  const textFingerprints = await Promise.all(
    Array.from(flaggedTexts).map((t) => sha256Hex(new TextEncoder().encode(t))),
  );
  const photoFingerprints = await Promise.all(flaggedImages.map((img) => sha256Hex(img)));
  const fingerprints = [...textFingerprints, ...photoFingerprints];
  const parts: BlockPart[] = [];
  if (photoFlagged) {
    parts.push({
      kind: "photo",
      categories: Array.from(kindCategories.photo).sort(),
      fingerprints: Array.from(new Set(photoFingerprints)),
      scores: kindScores.photo,
      imageKeys: Array.from(flaggedKeys),
    });
  }
  if (textFlagged) {
    parts.push({
      kind: "text",
      categories: Array.from(kindCategories.text).sort(),
      fingerprints: Array.from(new Set(textFingerprints)),
      scores: kindScores.text,
    });
  }
  return {
    status: "flagged",
    categories: Array.from(flagged).sort(),
    photo: photoFlagged,
    text: textFlagged,
    fingerprints: Array.from(new Set(fingerprints)),
    scores,
    parts,
    textFlags: Array.from(textFlagMap, ([text, cats]) => ({ text, categories: Array.from(cats).sort() })),
  };
}

async function sha256Hex(data: Uint8Array): Promise<string> {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", data));
  return Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
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
