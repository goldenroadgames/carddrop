import { createClient } from "jsr:@supabase/supabase-js@2";

// Deletes one reply (row and photo file) from one of the caller's cards.
// Senders have no delete right on replies and no write access to the
// reply-photos bucket, so this runs with the service role after checking the
// caller owns the card. A reported card is kept as evidence and is locked.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PHOTO_MARKER = "/storage/v1/object/public/reply-photos/";

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

    const { replyID } = await req.json().catch(() => ({}));
    if (typeof replyID !== "string" || !UUID_RE.test(replyID)) {
      return json({ error: "replyID required" }, 400);
    }

    const { data: reply } = await supabase
      .from("replies")
      .select("id, card_id, reply_image_url")
      .eq("id", replyID)
      .maybeSingle();
    if (!reply) return json({ status: "not_found" });

    const { data: card } = await supabase
      .from("cards")
      .select("sender_id, reported_at")
      .eq("id", reply.card_id)
      .maybeSingle();
    if (!card || card.sender_id !== user.id) return json({ error: "unauthorized" }, 403);
    if (card.reported_at) return json({ error: "unavailable" }, 403);

    const { error: deleteError } = await supabase.from("replies").delete().eq("id", reply.id);
    if (deleteError) {
      console.error("delete-reply error:", deleteError);
      return json({ error: "delete_failed" }, 500);
    }

    // Remove the photo file. The stored URL is the public URL; the object path
    // is everything after the bucket name.
    const url: string | null = reply.reply_image_url;
    const at = url ? url.indexOf(PHOTO_MARKER) : -1;
    if (url && at >= 0) {
      const path = decodeURIComponent(url.slice(at + PHOTO_MARKER.length).split("?")[0]);
      const { error: rmError } = await supabase.storage.from("reply-photos").remove([path]);
      if (rmError) console.error("delete-reply photo remove error:", rmError);
    }

    return json({ status: "deleted" });
  } catch (err) {
    console.error("delete-reply error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
