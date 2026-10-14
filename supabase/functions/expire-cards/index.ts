import { createClient } from "jsr:@supabase/supabase-js@2";
import { purgeCard, TOMBSTONE_BLANKING } from "../_shared/purgeCard.ts";

// Scheduled hourly (Supabase Cron + pg_net, x-cron-secret header matching the
// CRON_SECRET secret; deploy with --no-verify-jwt). Removes our stored copy of
// every card whose link has expired: replies, reactions, views, recipient rows
// and every image file (purgeCard), then blanks the card's content columns and
// stamps purged_at.
//
// Deliberately NOT deleteCard: the row is kept and deleted_at is NOT set, so the
// sender can still send the card again (resend-card answers needs_upload and
// send-card refills the row and clears purged_at). The row must stay anyway:
// physical_orders.card_id references cards(id) ON DELETE CASCADE.
//
// Skipped: cards that are deleted, reported or on legal hold (their own
// retention rules), cards with no expiry, and cards with a print order in the
// last ORDER_GUARD_DAYS (Lob may not have fetched the print files yet).
// marketing-cards copies are never touched by purgeCard.
const BATCH_LIMIT = 400;        // cards selected per run
const CONCURRENCY = 10;         // cards purged at once
const TIME_BUDGET_MS = 75_000;  // stop starting new cards after this
const ORDER_GUARD_DAYS = 7;

Deno.serve(async (req) => {
  try {
    const cronSecret = Deno.env.get("CRON_SECRET");
    const given = req.headers.get("x-cron-secret");
    if (!cronSecret || !given || given !== cronSecret) return json({ error: "unauthorized" }, 401);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const started = Date.now();
    const nowIso = new Date().toISOString();

    const { data: candidates, error } = await supabase
      .from("cards")
      .select("id, sender_id")
      .not("expires_at", "is", null)
      .lt("expires_at", nowIso)
      .is("deleted_at", null)
      .is("reported_at", null)
      .eq("legal_hold", false)
      .is("purged_at", null)
      .order("expires_at", { ascending: true })
      .limit(BATCH_LIMIT);
    if (error) return json({ error: error.message }, 500);

    const cards = candidates ?? [];
    if (cards.length === 0) return json({ selected: 0, purged: 0, failed: 0, skippedRecentOrder: 0, skippedNotExpired: 0, leftover: 0 });

    // Cards with a recent print order are left alone for now.
    const guardCutoff = new Date(Date.now() - ORDER_GUARD_DAYS * 86400000).toISOString();
    const { data: recent } = await supabase
      .from("physical_orders")
      .select("card_id")
      .in("card_id", cards.map((c) => c.id))
      .gt("created_at", guardCutoff);
    const recentOrder = new Set((recent ?? []).map((r: { card_id: string }) => r.card_id));

    let purged = 0;
    let failed = 0;
    let skippedNotExpired = 0;
    let next = 0;
    const todo = cards.filter((c) => !recentOrder.has(c.id));

    async function worker() {
      while (next < todo.length && Date.now() - started < TIME_BUDGET_MS) {
        const card = todo[next++];

        // Re-check just before purging: a resend may have revived this card
        // since the list was read.
        const { data: fresh } = await supabase
          .from("cards")
          .select("expires_at, deleted_at, reported_at, legal_hold, purged_at")
          .eq("id", card.id)
          .maybeSingle();
        if (!fresh || fresh.deleted_at || fresh.reported_at || fresh.legal_hold || fresh.purged_at ||
            !fresh.expires_at || new Date(fresh.expires_at).getTime() >= Date.now()) {
          skippedNotExpired++;
          continue;
        }

        const purgeError = await purgeCard(supabase, card.id, card.sender_id);
        if (purgeError) {
          failed++;
          console.error("expire purge error:", card.id, purgeError);
          continue;
        }
        const { error: updateError } = await supabase
          .from("cards")
          .update({ ...TOMBSTONE_BLANKING, purged_at: new Date().toISOString() })
          .eq("id", card.id);
        if (updateError) {
          failed++;
          console.error("expire update error:", card.id, updateError.message);
          continue;
        }
        purged++;
      }
    }
    await Promise.all(Array.from({ length: CONCURRENCY }, () => worker()));

    return json({
      selected: cards.length,
      purged,
      failed,
      skippedRecentOrder: recentOrder.size,
      skippedNotExpired,
      leftover: Math.max(0, todo.length - next),
      ms: Date.now() - started,
    });
  } catch (err) {
    console.error("expire-cards error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
