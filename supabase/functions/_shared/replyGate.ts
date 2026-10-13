import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

// Shared by submit-reply and submit-reaction: may a web visitor add a reply or
// reaction to this card right now? Not if the card is deleted, reported, on legal hold, owned
// by a suspended account, or the sender has switched replies off (on the card
// or in their profile; the profile switch overrides the card).
export type ReplyGate =
  | { ok: true; card: { id: string; sender_id: string | null } }
  | { ok: false; error: "unavailable" | "replies_off" };

export async function checkCardAcceptsReplies(
  supabase: SupabaseClient,
  cardID: string,
): Promise<ReplyGate> {
  const { data: card } = await supabase
    .from("cards")
    .select("id, sender_id, deleted_at, reported_at, legal_hold, replies_enabled")
    .eq("id", cardID)
    .maybeSingle();
  if (!card || card.deleted_at || card.reported_at || card.legal_hold) return { ok: false, error: "unavailable" };

  if (card.sender_id) {
    const { data: ban } = await supabase
      .from("account_bans")
      .select("user_id")
      .eq("user_id", card.sender_id)
      .is("reinstated_at", null)
      .maybeSingle();
    if (ban) return { ok: false, error: "unavailable" };

    const { data: sender } = await supabase
      .from("users")
      .select("replies_enabled")
      .eq("id", card.sender_id)
      .maybeSingle();
    if (sender && sender.replies_enabled === false) return { ok: false, error: "replies_off" };
  }

  if (card.replies_enabled === false) return { ok: false, error: "replies_off" };
  return { ok: true, card: { id: card.id, sender_id: card.sender_id } };
}
