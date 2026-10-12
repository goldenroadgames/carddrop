import { createClient } from "jsr:@supabase/supabase-js@2";
import { deleteAccountData } from "../_shared/deleteAccount.ts";
import { revokeAppleAccess } from "../_shared/appleRevoke.ts";

// Deletes the caller's account: every card (via the same routine as card
// delete), any leftover files, saved addresses, notices, the users row and the
// login itself; revokes Sign in with Apple when the app supplies a fresh
// authorization code.
//
// What is deliberately kept: see _shared/deleteAccount.ts (the same routine the
// sweeper uses for final suspensions). Originally (see carddrop/card_delete_complaints_bans_plan.md):
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

    // 2. Everything else (cards, files, orders, address book, notices, users
    //    row, the login): shared with the sweeper's final-suspension cleanup.
    const result = await deleteAccountData(supabase, uid);
    if (!result.ok) return fail(result.step, result.message);

    return json({ status: "deleted", appleRevoked });
  } catch (err) {
    console.error("delete-account error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

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
