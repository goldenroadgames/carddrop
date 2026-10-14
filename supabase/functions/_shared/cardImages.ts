import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { moderateContent, type ModerationVerdict } from "./moderation.ts";

// Card image files are uploaded by the app to the PRIVATE card-staging bucket
// ({userId}/{cardId}...), where nothing is public. Only this server code
// writes the public card-images bucket: it moderates the staged files first,
// then copies the ones that passed across, so a modified app can neither
// host arbitrary files nor swap an image after it was checked.
//
//   web files    {id}.jpg _back _back6x9 _thumb _before _before_thumb
//                -> moderated, then promoted to card-images (public)
//   print files  {id}_front_forLOB_<size>.jpg / _back_forLOB_<size>.jpg
//                -> moderated, then promoted to card-images (Lob fetches them)
//   private      {id}_full.jpg _before_full.jpg
//                -> moderated, then copied to card-private (not public; the
//                   admin marketing copy later moves them to marketing-cards)
const WEB_SUFFIXES = ["", "_back", "_back6x9", "_thumb", "_before", "_before_thumb"];
const PRIVATE_SUFFIXES = ["_full", "_before_full"];
const STAGING = "card-staging";
const HOLDING = "card-holding";
const PUBLIC = "card-images";
const PRIVATE = "card-private";

export type PromoteResult =
  | { status: "ok"; promoted: string[] }
  | { status: "flagged"; verdict: Extract<ModerationVerdict, { status: "flagged" }> }
  | { status: "error" }
  | { status: "missing"; names: string[] };

// requiredNames: file names that must exist either staged or already public.
export async function moderateAndPromote(
  supabase: SupabaseClient,
  userId: string,
  cardID: string,
  opts: { texts?: string[]; requireWeb?: boolean; printNames?: string[] },
): Promise<PromoteResult> {
  const id = cardID.toLowerCase();
  const folder = userId;

  const staged = await listNames(supabase, STAGING, folder, id);
  if (staged === null) return { status: "error" };
  const publicNames = new Set(await listNames(supabase, PUBLIC, folder, id) ?? []);

  const webNames = WEB_SUFFIXES.map((s) => `${id}${s}.jpg`).filter((n) => staged.has(n));
  const printNames = (opts.printNames ?? []).filter((n) => staged.has(n));
  const privateNames = PRIVATE_SUFFIXES.map((s) => `${id}${s}.jpg`).filter((n) => staged.has(n));

  // Required files: staged now, or (print files only) already promoted earlier.
  const missing: string[] = [];
  if (opts.requireWeb) {
    for (const n of [`${id}.jpg`, `${id}_back.jpg`]) if (!staged.has(n)) missing.push(n);
  }
  for (const n of opts.printNames ?? []) if (!staged.has(n) && !publicNames.has(n)) missing.push(n);
  if (missing.length > 0) return { status: "missing", names: missing };

  // Freeze the bytes first: copy every file to the server-only holding bucket
  // (the client can write card-staging, so it could swap a staged file after
  // it was checked). Moderate and promote from the holding copies only.
  const publicFiles = [...webNames, ...printNames];
  const toCheck = [...publicFiles, ...privateNames];
  const heldKeys = toCheck.map((n) => `${folder}/${n}`);
  // Files are independent, so each step runs for all of them at once (a card
  // has about ten).
  const holdResults = await Promise.all(heldKeys.map(async (key) => {
    await supabase.storage.from(HOLDING).remove([key]);
    const { error } = await supabase.storage.from(STAGING).copy(key, key, { destinationBucket: HOLDING });
    if (error) console.error("hold copy error:", key, error.message);
    return !error;
  }));
  if (holdResults.includes(false)) {
    await removeHeld(supabase, heldKeys);
    return { status: "error" };
  }

  // Moderate every held file. OpenAI fetches each one through a short-lived
  // signed URL.
  const signed = await Promise.all(heldKeys.map(async (key) => {
    const { data, error } = await supabase.storage.from(HOLDING).createSignedUrl(key, 600);
    return error || !data?.signedUrl ? null : { url: data.signedUrl, key };
  }));
  const imageUrls = signed.filter((x): x is { url: string; key: string } => x !== null);
  if (imageUrls.length !== heldKeys.length) {
    await removeHeld(supabase, heldKeys);
    return { status: "error" };
  }
  const verdict = await moderateContent(supabase, { texts: opts.texts, imageUrls });
  if (verdict.status === "error") {
    await removeHeld(supabase, heldKeys);
    return { status: "error" };
  }
  if (verdict.status === "flagged") {
    await removeHeld(supabase, heldKeys);
    await removeStaged(supabase, folder, id);
    return { status: "flagged", verdict };
  }

  // Clean: copy the held (checked) files across (remove first so a re-send
  // replaces the old copy), then clear the held and staged files.
  const jobs = [
    ...publicFiles.map((name) => ({ name, bucket: PUBLIC })),
    ...privateNames.map((name) => ({ name, bucket: PRIVATE })),
  ];
  const copied = await Promise.all(jobs.map(async ({ name, bucket }) => {
    const to = `${folder}/${name}`;
    await supabase.storage.from(bucket).remove([to]);
    const { error } = await supabase.storage.from(HOLDING).copy(to, to, { destinationBucket: bucket });
    if (error) console.error("promote copy error:", name, error.message);
    return error ? null : name;
  }));
  if (copied.includes(null)) {
    await removeHeld(supabase, heldKeys);
    return { status: "error" };
  }
  const promoted = copied as string[];
  await removeHeld(supabase, heldKeys);
  await removeStaged(supabase, folder, id);
  return { status: "ok", promoted };
}

// Removes held copies (best effort; holding is server-only and short-lived).
async function removeHeld(supabase: SupabaseClient, keys: string[]) {
  if (keys.length > 0) await supabase.storage.from(HOLDING).remove(keys);
}

// Removes every staged file for a card.
export async function removeStaged(supabase: SupabaseClient, folder: string, id: string) {
  const names = await listNames(supabase, STAGING, folder, id);
  if (names && names.size > 0) {
    await supabase.storage.from(STAGING).remove(Array.from(names, (n) => `${folder}/${n}`));
  }
}

async function listNames(
  supabase: SupabaseClient,
  bucket: string,
  folder: string,
  search: string,
): Promise<Set<string> | null> {
  const out = new Set<string>();
  for (let offset = 0; offset < 1000; offset += 100) {
    const { data, error } = await supabase.storage.from(bucket).list(folder, { limit: 100, offset, search });
    if (error) {
      console.error("list error:", bucket, error.message);
      return null;
    }
    for (const o of data ?? []) if (o.id !== null) out.add(o.name);
    if (!data || data.length < 100) break;
  }
  return out;
}

// Which part of the card a staged image key is: the finished front, the finished
// back, or the person's original photo. Keys look like {userId}/{cardId}{suffix}.jpg
// (a card id is a 36-character UUID with no underscore).
export function imageRole(key: string): "front" | "back" | "original" | "other" {
  const name = (key.split("/").pop() ?? "").replace(/\.jpg$/i, "");
  const suffix = name.slice(36);
  if (suffix === "" || suffix === "_thumb" || suffix === "_full" || suffix.startsWith("_front_forLOB")) return "front";
  if (suffix === "_back" || suffix === "_back6x9" || suffix.startsWith("_back_forLOB")) return "back";
  if (suffix === "_before" || suffix === "_before_thumb" || suffix === "_before_full") return "original";
  return "other";
}
