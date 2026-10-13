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
//                -> NOT moderated, so never public: copied to card-private
//                   (used only by the admin marketing copy)
const WEB_SUFFIXES = ["", "_back", "_back6x9", "_thumb", "_before", "_before_thumb"];
const PRIVATE_SUFFIXES = ["_full", "_before_full"];
const STAGING = "card-staging";
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

  // Moderate every file that will become public. OpenAI fetches each one
  // through a short-lived signed URL.
  const toCheck = [...webNames, ...printNames];
  const imageUrls: { url: string; key: string }[] = [];
  for (const name of toCheck) {
    const { data, error } = await supabase.storage.from(STAGING).createSignedUrl(`${folder}/${name}`, 600);
    if (error || !data?.signedUrl) return { status: "error" };
    imageUrls.push({ url: data.signedUrl, key: `${folder}/${name}` });
  }
  const verdict = await moderateContent(supabase, { texts: opts.texts, imageUrls });
  if (verdict.status === "error") return { status: "error" };
  if (verdict.status === "flagged") {
    await removeStaged(supabase, folder, id);
    return { status: "flagged", verdict };
  }

  // Clean: copy across (remove first so a re-send replaces the old copy),
  // then clear the staged files.
  const promoted: string[] = [];
  for (const [names, bucket] of [[toCheck, PUBLIC], [privateNames, PRIVATE]] as const) {
    for (const name of names) {
      const to = `${folder}/${name}`;
      await supabase.storage.from(bucket).remove([to]);
      const { error } = await supabase.storage.from(STAGING).copy(to, to, { destinationBucket: bucket });
      if (error) {
        console.error("promote copy error:", name, error.message);
        return { status: "error" };
      }
      promoted.push(name);
    }
  }
  await removeStaged(supabase, folder, id);
  return { status: "ok", promoted };
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
  if (suffix === "" || suffix === "_thumb" || suffix.startsWith("_front_forLOB")) return "front";
  if (suffix === "_back" || suffix === "_back6x9" || suffix.startsWith("_back_forLOB")) return "back";
  if (suffix === "_before" || suffix === "_before_thumb") return "original";
  return "other";
}
