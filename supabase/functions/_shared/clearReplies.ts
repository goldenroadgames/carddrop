import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

// Deletes every reply and every emoji reaction on the given cards. Returns an
// error message, or null on success. Safe to retry.
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

  return null;
}
