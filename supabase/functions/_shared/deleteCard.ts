import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { purgeCard, TOMBSTONE_BLANKING } from "./purgeCard.ts";

// Marks a card deleted (the shared link dies), blanks its content, purges
// every file and child row, and stamps purged_at. Safe to repeat. Returns an
// error message, or null when the card is fully gone.
export async function deleteCard(
  supabase: SupabaseClient,
  card: { id: string; sender_id: string; deleted_at: string | null },
): Promise<string | null> {
  // Last line of defence: a card on legal hold is never deleted, whichever
  // caller got here.
  const { data: held } = await supabase.from("cards").select("legal_hold").eq("id", card.id).maybeSingle();
  if (held?.legal_hold) return "legal hold";

  if (!card.deleted_at) {
    const { error } = await supabase
      .from("cards")
      .update({ deleted_at: new Date().toISOString(), ...TOMBSTONE_BLANKING })
      .eq("id", card.id);
    if (error) return `mark: ${error.message}`;
  }

  const purgeError = await purgeCard(supabase, card.id, card.sender_id);
  if (purgeError) return purgeError;

  const { error } = await supabase
    .from("cards")
    .update({ purged_at: new Date().toISOString() })
    .eq("id", card.id);
  return error ? `purged_at: ${error.message}` : null;
}
