import { createClient } from "jsr:@supabase/supabase-js@2";

// Called by the app when a SENT card is reopened to send again. Decides
// whether the card can be shared as is, without any upload:
//   unavailable  — the card is deleted, reported or on hold (or isn't the
//                  caller's). The app says it can't be resent and hides it.
//   needs_upload — the card row or its digital files ({id}.jpg, {id}_back.jpg
//                  in card-images) are gone. The app then re-uploads from the
//                  phone through the normal send-card path (full moderation,
//                  fresh expiry).
//   live         — files are there. The expiry is pushed out to now +
//                  card_link_days (never shortened, even if it had already
//                  lapsed: the files were moderated when first sent and a
//                  card's content never changes under the same id). The app
//                  shares the existing link.
// Not counted against the send rate caps: nothing new is uploaded or checked.
// Body: { cardID }.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DEFAULT_LINK_DAYS = 90;
const DAY_MS = 24 * 60 * 60 * 1000;

Deno.serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "unauthorized" }, 401);
    const { data: { user }, error: authError } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
    if (authError || !user) return json({ error: "unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    const cardID = typeof body.cardID === "string" ? body.cardID.toLowerCase() : "";
    if (!UUID_RE.test(cardID)) return json({ error: "invalid" }, 400);

    const { data: card } = await supabase
      .from("cards")
      .select("sender_id, deleted_at, reported_at, legal_hold, expires_at")
      .eq("id", cardID)
      .maybeSingle();

    if (!card) return json({ status: "needs_upload" });
    if (card.sender_id !== user.id) return json({ status: "unavailable" });
    if (card.deleted_at || card.reported_at || card.legal_hold) return json({ status: "unavailable" });

    // Both digital files must still be in the public bucket.
    const { data: files, error: listError } = await supabase.storage
      .from("card-images")
      .list(user.id, { limit: 100, search: cardID });
    if (listError) {
      console.error("resend-card list error:", listError.message);
      return json({ error: "unavailable_try_again" }, 500);
    }
    const names = new Set((files ?? []).map((f) => f.name));
    if (!names.has(`${cardID}.jpg`) || !names.has(`${cardID}_back.jpg`)) {
      return json({ status: "needs_upload" });
    }

    // Push the expiry out. A card with no expiry is left alone.
    let expiresAt: string | null = card.expires_at;
    if (card.expires_at) {
      const { data: cfg } = await supabase
        .from("zz_config")
        .select("value")
        .eq("key", "card_link_days")
        .maybeSingle();
      const parsed = parseInt(cfg?.value ?? "", 10);
      const days = parsed > 0 ? parsed : DEFAULT_LINK_DAYS;
      const target = Date.now() + days * DAY_MS;
      if (target > new Date(card.expires_at).getTime()) {
        expiresAt = new Date(target).toISOString();
        const { error: updateError } = await supabase
          .from("cards")
          .update({ expires_at: expiresAt })
          .eq("id", cardID);
        if (updateError) {
          console.error("resend-card update error:", updateError.message);
          return json({ error: "unavailable_try_again" }, 500);
        }
      }
    }

    return json({ status: "live", expiresAt });
  } catch (e) {
    console.error("resend-card error:", e);
    return json({ error: "unavailable_try_again" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
