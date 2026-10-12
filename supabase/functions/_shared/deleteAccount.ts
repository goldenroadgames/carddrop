import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { deleteCard } from "./deleteCard.ts";

// Deletes one account's data: every card (via the same routine as card
// delete), leftover files, saved addresses, notices, the users row and the
// login itself. Shared by the app's delete-account function and the sweeper's
// final-suspension cleanup.
//
// Deliberately KEPT (see carddrop/card_delete_complaints_bans_plan.md):
//   - REPORTED cards, with their images and replies, until the sweeper deletes
//     them 12 months after the report (evidence)
//   - card tombstones (so recipients can still report an old card)
//   - physical_orders, with the sender link and the sender's own name/address
//     removed; the recipient snapshot stays until the 12-month sweep
//   - complaints, mail blocks, account_bans (a ban survives deletion),
//     content_blocks, user_devices rows (send caps and bans are per device)
//   - marketing copies
// Idempotent: if it fails partway it can simply be run again. A login that is
// already gone counts as success.
export type DeleteAccountResult = { ok: true } | { ok: false; step: string; message: string };

export async function deleteAccountData(supabase: SupabaseClient, uid: string): Promise<DeleteAccountResult> {
  const fail = (step: string, message: string): DeleteAccountResult => ({ ok: false, step, message });

  // 1. Every card not yet fully purged.
  const { data: cards, error: cardsError } = await supabase
    .from("cards")
    .select("id, sender_id, deleted_at")
    .eq("sender_id", uid)
    .is("purged_at", null)
    .is("reported_at", null)    // reported cards are kept as evidence
    .eq("legal_hold", false);   // so are cards on legal hold
  if (cardsError) return fail("cards lookup", cardsError.message);
  for (const card of cards ?? []) {
    const err = await deleteCard(supabase, card);
    if (err) return fail("delete card " + card.id, err);
  }

  // 2. Anything else left in the user's image folder (uploads for cards that
  //    never completed, for example). Files of reported cards are skipped.
  const { data: reportedCards } = await supabase
    .from("cards")
    .select("id")
    .eq("sender_id", uid)
    .or("reported_at.not.is.null,legal_hold.eq.true");
  const keepPrefixes = (reportedCards ?? []).map((c) => c.id.toLowerCase());
  for (const bucket of ["card-images", "card-staging", "card-private"]) {
    const folderError = await removeFolderExcept(supabase, bucket, uid.toLowerCase(), keepPrefixes);
    if (folderError) return fail("image folder", folderError);
  }

  // 3. Orders: unlink the sender and drop the sender's own name/address; the
  //    recipient snapshot stays for the 12-month sweep. Address-book links
  //    must be cleared before the address book rows go.
  {
    const { error } = await supabase
      .from("physical_orders")
      .update({
        sender_id: null,
        sender_first_name: null, sender_last_name: null, sender_street: null,
        sender_city: null, sender_state: null, sender_zip: null, sender_country: null,
        sender_address_book_id: null,
        recipient_address_book_id: null,
      })
      .eq("sender_id", uid);
    if (error) return fail("orders", error.message);
  }

  // 4. The user's own rows.
  for (const [table, column] of [
    ["user_address_book", "user_id"],
    ["user_notices", "user_id"],
    ["users", "id"],
  ] as const) {
    const { error } = await supabase.from(table).delete().eq(column, uid);
    if (error) return fail(table, error.message);
  }

  // 5. The login itself (last, so a failed run can be retried).
  const { error: deleteUserError } = await supabase.auth.admin.deleteUser(uid);
  if (deleteUserError && !/not found/i.test(deleteUserError.message)) {
    return fail("auth user", deleteUserError.message);
  }

  return { ok: true };
}

// Removes every file in the user's folder of a card bucket except those that belong
// to the kept (reported) cards, i.e. whose name starts with a kept card id.
// Pages through with an offset so kept files don't stall the loop.
async function removeFolderExcept(
  supabase: SupabaseClient,
  bucket: string,
  folder: string,
  keepPrefixes: string[],
): Promise<string | null> {
  const toRemove: string[] = [];
  for (let offset = 0; offset < 5000; offset += 100) {
    const { data, error } = await supabase.storage.from(bucket).list(folder, { limit: 100, offset });
    if (error) return `${bucket} list: ${error.message}`;
    if (!data || data.length === 0) break;
    for (const o of data) {
      if (o.id === null) continue; // sub-folder placeholder
      const name = o.name.toLowerCase();
      if (keepPrefixes.some((k) => name.startsWith(k))) continue;
      toRemove.push(`${folder}/${o.name}`);
    }
  }
  for (let i = 0; i < toRemove.length; i += 100) {
    const { error } = await supabase.storage.from(bucket).remove(toRemove.slice(i, i + 100));
    if (error) return `${bucket} remove: ${error.message}`;
  }
  return null;
}
