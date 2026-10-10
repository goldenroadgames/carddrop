import { createClient } from "jsr:@supabase/supabase-js@2";
import { deleteCard } from "../_shared/deleteCard.ts";

// Deletes one of the caller's cards: marks it deleted (the shared link dies
// immediately), blanks its content, then purges every file and child row.
// If the purge fails partway the card is already dead to the public and the
// sweep-deleted-cards function finishes it later, so this is safe to retry.
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

    const { cardID } = await req.json();
    if (!cardID) return json({ error: "cardID required" }, 400);

    const { data: card } = await supabase
      .from("cards")
      .select("id, sender_id, deleted_at, purged_at")
      .eq("id", cardID)
      .maybeSingle();

    // Never uploaded (a plain draft), or already gone: nothing to do.
    if (!card) return json({ status: "not_found" });
    if (card.sender_id !== user.id) return json({ error: "unauthorized" }, 403);
    if (card.purged_at) return json({ status: "deleted" });

    const deleteError = await deleteCard(supabase, card);
    if (deleteError) {
      console.error("delete-card error:", deleteError);
      return json({ error: "delete_incomplete" }, 500);
    }

    return json({ status: "deleted" });
  } catch (err) {
    console.error("delete-card error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
