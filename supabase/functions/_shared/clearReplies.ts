import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { removeFolder } from "./purgeCard.ts";

// Deletes every reply (rows and photo files) and every emoji reaction on the
// given cards. Rows first, then files, like purgeCard. Returns an error
// message, or null on success. Safe to retry.
export async function clearReplies(
  supabase: SupabaseClient,
  cardIDs: string[],
): Promise<string | null> {
  const ids = cardIDs.map((c) => c.toLowerCase());

  for (let i = 0; i < ids.length; i += 100) {
    const chunk = ids.slice(i, i + 100);
    for (const table of ["replies", "reactions"]) {
      const { error } = await supabase.from(table).delete().in("card_id", chunk);
      if (error) return `${table}: ${error.message}`;
    }
  }

  // Reply photos live in reply-photos/{cardId}/..., where the folder is
  // whatever case the card link used, so try both (same as purgeCard).
  for (const id of ids) {
    for (const folder of new Set([id, id.toUpperCase()])) {
      const err = await removeFolder(supabase, "reply-photos", folder, undefined);
      if (err) return err;
    }
  }
  return null;
}
