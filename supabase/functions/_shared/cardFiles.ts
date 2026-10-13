import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

// A card's image files live in the PUBLIC card-images bucket only while the
// card is neither reported nor on legal hold. While it is either, they live in
// the PRIVATE card-private bucket (same path), so nobody with the old web
// address can open them; the admin pages show them through short-lived signed
// links after the held-cards password.
//
//   secureCardFiles   card-images -> card-private  (report, legal hold)
//   restoreCardFiles  card-private -> card-images  (dismissed / released, and
//                     neither reported nor held any more)
//
// syncCardFiles looks the card up and puts its files where its CURRENT state says:
// private if reported or held, public otherwise. Callers change the flags first,
// then call it. Both moves are safe to run twice. Each file is copied (an existing copy at the
// destination is removed first: copy 409s on an existing key), the copy is
// checked, then the source is removed, so a failure part-way never loses a
// file. Returns an error message, or null on success.
//
// Files named {cardId}_full / _before_full are ALREADY private (card-private)
// and are never moved to the public bucket.
const PUBLIC = "card-images";
const PRIVATE = "card-private";
const ALWAYS_PRIVATE = /_(?:before_)?full\.jpg$/i;

export async function secureCardFiles(
  supabase: SupabaseClient,
  cardID: string,
  senderID: string,
): Promise<string | null> {
  return await moveCardFiles(supabase, cardID, senderID, PUBLIC, PRIVATE);
}

export async function restoreCardFiles(
  supabase: SupabaseClient,
  cardID: string,
  senderID: string,
): Promise<string | null> {
  return await moveCardFiles(supabase, cardID, senderID, PRIVATE, PUBLIC);
}

async function moveCardFiles(
  supabase: SupabaseClient,
  cardID: string,
  senderID: string,
  from: string,
  to: string,
): Promise<string | null> {
  const id = cardID.toLowerCase();
  const folder = senderID.toLowerCase();

  const names: string[] = [];
  for (let offset = 0; offset < 1000; offset += 100) {
    const { data, error } = await supabase.storage.from(from).list(folder, { limit: 100, offset, search: id });
    if (error) return `${from} list: ${error.message}`;
    const page = (data ?? []).map((o) => o.name).filter((n) => n.toLowerCase().startsWith(id));
    names.push(...page);
    if ((data ?? []).length < 100) break;
  }

  for (const name of names) {
    // The print-scale originals belong in the private bucket whatever the card's state.
    if (to === PUBLIC && ALWAYS_PRIVATE.test(name)) continue;
    const path = `${folder}/${name}`;
    await supabase.storage.from(to).remove([path]);
    const { error: copyError } = await supabase.storage.from(from).copy(path, path, { destinationBucket: to });
    if (copyError) return `copy ${name}: ${copyError.message}`;
    const { data: check } = await supabase.storage.from(to).list(folder, { limit: 5, search: name });
    if (!(check ?? []).some((o) => o.name === name)) return `copy ${name}: not found at destination`;
    const { error: removeError } = await supabase.storage.from(from).remove([path]);
    if (removeError) return `remove ${name}: ${removeError.message}`;
  }
  return null;
}

// Files go where the card's current state says: private while reported or on
// legal hold, public otherwise. A deleted card is left to the delete routines.
export async function syncCardFiles(supabase: SupabaseClient, cardID: string): Promise<string | null> {
  const { data: card, error } = await supabase
    .from("cards")
    .select("id, sender_id, reported_at, legal_hold, deleted_at")
    .eq("id", cardID)
    .maybeSingle();
  if (error) return `card lookup: ${error.message}`;
  if (!card || !card.sender_id || card.deleted_at) return null;
  return card.reported_at || card.legal_hold
    ? await secureCardFiles(supabase, card.id, card.sender_id)
    : await restoreCardFiles(supabase, card.id, card.sender_id);
}
