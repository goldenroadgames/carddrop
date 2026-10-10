import { createClient } from "jsr:@supabase/supabase-js@2";
import { purgeCard } from "../_shared/purgeCard.ts";

// Scheduled job: finishes deletes that failed partway (deleted_at set,
// purged_at null) and runs the 12-month retention scrubs. Called by Supabase
// Cron (pg_net) with an x-cron-secret header matching the CRON_SECRET secret.
// Deploy with --no-verify-jwt (the cron call carries no JWT); the shared
// secret is the only gate, so anything without it is rejected.
Deno.serve(async (req) => {
  try {
    const cronSecret = Deno.env.get("CRON_SECRET");
    const given = req.headers.get("x-cron-secret");
    if (!cronSecret || !given || given !== cronSecret) return json({ error: "unauthorized" }, 401);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const { data: pending, error } = await supabase
      .from("cards")
      .select("id, sender_id")
      .not("deleted_at", "is", null)
      .is("purged_at", null)
      .limit(50);
    if (error) return json({ error: error.message }, 500);

    let purged = 0;
    let failed = 0;
    for (const card of pending ?? []) {
      const purgeError = await purgeCard(supabase, card.id, card.sender_id);
      if (purgeError) {
        failed++;
        console.error("sweep purge error:", card.id, purgeError);
        continue;
      }
      await supabase
        .from("cards")
        .update({ purged_at: new Date().toISOString() })
        .eq("id", card.id);
      purged++;
    }

    // ---------------- retention (12 months) ----------------
    // Complaint text, order name/address snapshots and the digital send log
    // are kept 12 months. Financial columns on orders are kept (7 years).
    const cutoff = new Date(Date.now() - 365 * 86400000).toISOString();
    const retention: Record<string, string | null> = {};
    const steps: [string, PromiseLike<{ error: { message: string } | null }>][] = [
      ["complaint_text", supabase.from("card_complaints")
        .update({ complaint_text: null }).lt("created_at", cutoff).not("complaint_text", "is", null)],
      ["order_snapshots", supabase.from("physical_orders").update({
        recipient_first_name: null, recipient_last_name: null, recipient_street: null,
        recipient_city: null, recipient_state: null, recipient_zip: null, recipient_country: null,
        sender_first_name: null, sender_last_name: null, sender_street: null,
        sender_city: null, sender_state: null, sender_zip: null, sender_country: null,
        scrubbed_at: new Date().toISOString(),
      }).lt("created_at", cutoff).is("scrubbed_at", null)],
      ["send_log", supabase.from("card_recipients").delete().lt("created_at", cutoff)],
    ];
    for (const [name, op] of steps) {
      const { error: opError } = await op;
      retention[name] = opError ? opError.message : null;
      if (opError) console.error("sweep retention error:", name, opError.message);
    }

    return json({ purged, failed, retention });
  } catch (err) {
    console.error("sweep-deleted-cards error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
