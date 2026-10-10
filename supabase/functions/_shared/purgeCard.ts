import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

// Content columns blanked on a deleted card. The row itself stays as a
// tombstone (id, sender_id, sent_at, expires_at, is_portrait, deleted_at).
export const TOMBSTONE_BLANKING = {
  sender_nickname:    null,
  recipient_nickname: null,
  message_preview:    null,
  teaser_image_url:   null,
  thumbnail_url:      null,
  front_ink_message:  null,
  back_ink_message:   null,
  design_features:    null,
};

// Removes every file and child row for a card. Safe to run repeatedly (the
// sweeper retries). Does NOT touch physical_orders (kept for audit) or the
// marketing-cards copies (survive deletion by design).
// Returns the first error message, or null when everything is gone.
export async function purgeCard(
  supabase: SupabaseClient,
  cardID: string,
  senderID: string,
): Promise<string | null> {
  const id = cardID.toLowerCase();

  // Child rows first.
  for (const table of ["replies", "reactions", "card_views", "card_recipients"]) {
    const { error } = await supabase.from(table).delete().eq("card_id", id);
    if (error) return `${table}: ${error.message}`;
  }

  // Reply photos live in reply-photos/{cardId}/..., where cardId is whatever
  // case the link used (send-card builds the link from the app's uppercase
  // UUID), so try both.
  for (const folder of new Set([id, id.toUpperCase()])) {
    const err = await removeFolder(supabase, "reply-photos", folder, undefined);
    if (err) return err;
  }

  // Card images: no wildcard in the Storage API, so list the sender's folder
  // by cardID prefix and remove everything returned. Catches every variant
  // (_back, _thumb, _full, _before*, _front_forLOB_*, _back_forLOB_* ...).
  return await removeFolder(supabase, "card-images", senderID.toLowerCase(), id);
}

export async function removeFolder(
  supabase: SupabaseClient,
  bucket: string,
  folder: string,
  search: string | undefined,
): Promise<string | null> {
  // Loop in case there are more than one page of matches.
  for (let page = 0; page < 10; page++) {
    const { data, error } = await supabase.storage.from(bucket).list(folder, {
      limit: 100,
      search,
    });
    if (error) return `${bucket} list: ${error.message}`;
    const names = (data ?? [])
      .filter((o) => o.id !== null) // skip sub-folder placeholders
      .map((o) => `${folder}/${o.name}`);
    if (names.length === 0) return null;
    const { error: rmError } = await supabase.storage.from(bucket).remove(names);
    if (rmError) return `${bucket} remove: ${rmError.message}`;
  }
  return null;
}
