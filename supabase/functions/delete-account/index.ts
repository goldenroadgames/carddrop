import { createClient } from "jsr:@supabase/supabase-js@2";
import { deleteCard } from "../_shared/deleteCard.ts";
import { revokeAppleAccess } from "../_shared/appleRevoke.ts";

// Deletes the caller's account: every card (via the same routine as card
// delete), any leftover files, saved addresses, notices, the users row and the
// login itself; revokes Sign in with Apple when the app supplies a fresh
// authorization code.
//
// Deliberately KEPT (see carddrop/card_delete_complaints_bans_plan.md):
//   - REPORTED cards, with their images and replies, until the sweeper deletes
//     them 12 months after the report (evidence; the complaint also keeps the
//     sender's email for that long)
//   - card tombstones (so recipients can still report an old card)
//   - physical_orders, with the sender link and the sender's own name/address
//     removed; the recipient name/address snapshot stays until the 12-month
//     sweep so a recipient can still report the card and block mail
//   - complaints, mail blocks, account_bans (a ban survives deletion)
//   - user_devices rows (send caps and bans are per device)
//   - marketing copies
// Idempotent: if it fails partway, the app can simply call it again.
Deno.serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "unauthorized" }, 401);
    const jwt = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(jwt);
    if (authError || !user) return json({ error: "unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    const appleCode = typeof body.appleAuthorizationCode === "string" ? body.appleAuthorizationCode : null;
    const uid = user.id;

    // 1. Sign in with Apple: revoke first, while we still have the user.
    const isApple = (user.identities ?? []).some((i) => i.provider === "apple");
    let appleRevoked: boolean | null = null;
    if (isApple && appleCode) appleRevoked = await revokeAppleAccess(appleCode);

    // 2. Every card not yet fully purged.
    const { data: cards, error: cardsError } = await supabase
      .from("cards")
      .select("id, sender_id, deleted_at")
      .eq("sender_id", uid)
      .is("purged_at", null)
      .is("reported_at", null);   // reported cards are kept as evidence
    if (cardsError) return fail("cards lookup", cardsError.message);
    for (const card of cards ?? []) {
      const err = await deleteCard(supabase, card);
      if (err) return fail("delete card " + card.id, err);
    }

    // 3. Anything else left in the user's image folder (uploads for cards that
    //    never completed, for example).
    //    Files of reported cards are skipped (kept as evidence).
    const { data: reportedCards } = await supabase
      .from("cards")
      .select("id")
      .eq("sender_id", uid)
      .not("reported_at", "is", null);
    const keepPrefixes = (reportedCards ?? []).map((c) => c.id.toLowerCase());
    const folderError = await removeFolderExcept(supabase, uid.toLowerCase(), keepPrefixes);
    if (folderError) return fail("image folder", folderError);

    // 4. Orders: unlink the sender and drop the sender's own name/address; the
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

    // 5. The user's own rows.
    for (const [table, column] of [
      ["user_address_book", "user_id"],
      ["user_notices", "user_id"],
      ["users", "id"],
    ] as const) {
      const { error } = await supabase.from(table).delete().eq(column, uid);
      if (error) return fail(table, error.message);
    }

    // 6. The login itself (last, so a failed run can be retried with a valid token).
    const { error: deleteUserError } = await supabase.auth.admin.deleteUser(uid);
    if (deleteUserError) return fail("auth user", deleteUserError.message);

    return json({ status: "deleted", appleRevoked });
  } catch (err) {
    console.error("delete-account error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

// Removes every file in the user's card-images folder except those that belong
// to the kept (reported) cards, i.e. whose name starts with a kept card id.
// Pages through with an offset so kept files don't stall the loop.
async function removeFolderExcept(
  supabase: ReturnType<typeof createClient>,
  folder: string,
  keepPrefixes: string[],
): Promise<string | null> {
  const toRemove: string[] = [];
  for (let offset = 0; offset < 5000; offset += 100) {
    const { data, error } = await supabase.storage.from("card-images").list(folder, { limit: 100, offset });
    if (error) return `card-images list: ${error.message}`;
    if (!data || data.length === 0) break;
    for (const o of data) {
      if (o.id === null) continue; // sub-folder placeholder
      const name = o.name.toLowerCase();
      if (keepPrefixes.some((k) => name.startsWith(k))) continue;
      toRemove.push(`${folder}/${o.name}`);
    }
  }
  for (let i = 0; i < toRemove.length; i += 100) {
    const { error } = await supabase.storage.from("card-images").remove(toRemove.slice(i, i + 100));
    if (error) return `card-images remove: ${error.message}`;
  }
  return null;
}

function fail(step: string, message: string): Response {
  console.error(`delete-account failed at ${step}:`, message);
  return json({ error: "delete_incomplete", step }, 500);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
