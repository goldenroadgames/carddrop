import { createClient } from "jsr:@supabase/supabase-js@2";
import { purgeCard } from "../_shared/purgeCard.ts";
import { deleteCard } from "../_shared/deleteCard.ts";
import { deleteAccountData } from "../_shared/deleteAccount.ts";

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
        .update({ complaint_text: null, sender_email: null }).lt("created_at", cutoff)
        .or("complaint_text.not.is.null,sender_email.not.is.null")],
      ["order_snapshots", supabase.from("physical_orders").update({
        recipient_first_name: null, recipient_last_name: null, recipient_street: null,
        recipient_city: null, recipient_state: null, recipient_zip: null, recipient_country: null,
        sender_first_name: null, sender_last_name: null, sender_street: null,
        sender_city: null, sender_state: null, sender_zip: null, sender_country: null,
        scrubbed_at: new Date().toISOString(),
      }).lt("created_at", cutoff).is("scrubbed_at", null)],
      ["send_log", supabase.from("card_recipients").delete().lt("created_at", cutoff)],
      // Records of content blocked by moderation (no content, just who/kind/category/time).
      ["content_blocks", supabase.from("content_blocks").delete().lt("created_at", cutoff)],
    ];
    for (const [name, op] of steps) {
      const { error: opError } = await op;
      retention[name] = opError ? opError.message : null;
      if (opError) console.error("sweep retention error:", name, opError.message);
    }

    // Reported cards are kept as evidence for 12 months, then deleted like
    // any other card (blanked tombstone + files purged).
    const { data: expiredReports } = await supabase
      .from("cards")
      .select("id, sender_id, deleted_at")
      .not("reported_at", "is", null)
      .lt("reported_at", cutoff)
      .is("deleted_at", null)
      .limit(50);
    let reportedDeleted = 0;
    for (const card of expiredReports ?? []) {
      const err = await deleteCard(supabase, card);
      if (err) console.error("sweep reported-card error:", card.id, err);
      else reportedDeleted++;
    }

    // Final suspensions: delete the account's data final_suspension_delete_days
    // (default 30) after the suspension began, unless the ban is on legal hold.
    const finalSuspensions = await sweepFinalSuspensions(supabase);

    // Appeals nobody reviewed are closed after appeal_auto_deny_days.
    const staleAppeals = await closeStaleAppeals(supabase);

    // Suspended accounts that were never appealed or reinstated: housekeeping.
    const dormantSuspensions = await sweepDormantSuspensions(supabase);

    return json({ purged, failed, reportedDeleted, retention, finalSuspensions, staleAppeals, dormantSuspensions });
  } catch (err) {
    console.error("sweep-deleted-cards error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

// "Final" = the account has already been reinstated appeal_max_reinstatements
// times (by account, or by verified email) and is suspended again. Only those
// are deleted, never a suspension that can still be appealed. The ban rows are
// kept (that is what keeps the person out); purged_at stops a repeat.
// deno-lint-ignore no-explicit-any
async function markFinalDevicesPermanent(supabase: any, maxReinstatements: number): Promise<void> {
  const { data: active } = await supabase
    .from("account_bans")
    .select("user_id, email, final")
    .is("reinstated_at", null)
    .not("user_id", "is", null)
    .limit(200);
  for (const ban of active ?? []) {
    let isFinal = !!ban.final;
    if (!isFinal) {
      const emailOk = ban.email && !/[,()]/.test(ban.email);
      const { count } = await supabase
        .from("account_bans")
        .select("id", { count: "exact", head: true })
        .not("reinstated_at", "is", null)
        .or(`user_id.eq.${ban.user_id}${emailOk ? `,email.eq.${ban.email}` : ""}`);
      isFinal = (count ?? 0) >= maxReinstatements;
    }
    if (isFinal) await supabase.from("user_devices").update({ permanent: true }).eq("user_id", ban.user_id);
  }
}

// deno-lint-ignore no-explicit-any
async function sweepFinalSuspensions(supabase: any): Promise<{ deleted: number; failed: number }> {
  const { data: cfgRows } = await supabase
    .from("zz_config")
    .select("key, value")
    .in("key", ["final_suspension_delete_days", "appeal_max_reinstatements"]);
  const cfg: Record<string, number> = {};
  for (const r of cfgRows ?? []) cfg[r.key] = parseInt(r.value, 10);
  const days = cfg["final_suspension_delete_days"] > 0 ? cfg["final_suspension_delete_days"] : 30;
  const maxReinstatements = cfg["appeal_max_reinstatements"] >= 0 ? cfg["appeal_max_reinstatements"] : 2;
  const cutoff = new Date(Date.now() - days * 86400000).toISOString();

  // Devices of every final suspension become permanent as soon as the sweeper
  // sees it, not only at deletion time.
  await markFinalDevicesPermanent(supabase, maxReinstatements);

  const { data: bans } = await supabase
    .from("account_bans")
    .select("user_id, email, final")
    .is("reinstated_at", null)
    .eq("legal_hold", false)
    .is("purged_at", null)
    .not("user_id", "is", null)
    .lt("created_at", cutoff)
    .limit(50);

  let deleted = 0;
  let failed = 0;
  for (const ban of bans ?? []) {
    // Final by hand (final flag) or by count (reinstated maxReinstatements times).
    if (!ban.final) {
      const emailOk = ban.email && !/[,()]/.test(ban.email);
      const { count } = await supabase
        .from("account_bans")
        .select("id", { count: "exact", head: true })
        .not("reinstated_at", "is", null)
        .or(`user_id.eq.${ban.user_id}${emailOk ? `,email.eq.${ban.email}` : ""}`);
      if ((count ?? 0) < maxReinstatements) continue; // can still appeal: not final
    }

    // Mark the account's devices permanent BEFORE deleting (deleting the users
    // row clears user_devices.user_id).
    await supabase.from("user_devices").update({ permanent: true }).eq("user_id", ban.user_id);

    const result = await deleteAccountData(supabase, ban.user_id);
    if (!result.ok) {
      console.error("final-suspension delete failed:", ban.user_id, result.step, result.message);
      failed++;
      continue;
    }
    await supabase
      .from("account_bans")
      .update({ purged_at: new Date().toISOString() })
      .eq("user_id", ban.user_id)
      .is("reinstated_at", null);
    deleted++;
  }
  return { deleted, failed };
}

// A suspension that is still active suspension_delete_days (default 180) after it
// began, with no open appeal and no legal hold, has its account data deleted
// (same routine and kept records as a final suspension). purged_at stops a
// repeat; the ban rows stay.
// deno-lint-ignore no-explicit-any
async function sweepDormantSuspensions(supabase: any): Promise<{ deleted: number; failed: number }> {
  const { data: cfg } = await supabase
    .from("zz_config")
    .select("value")
    .eq("key", "suspension_delete_days")
    .maybeSingle();
  const parsed = parseInt(cfg?.value ?? "", 10);
  const days = parsed > 0 ? parsed : 180;
  const cutoff = new Date(Date.now() - days * 86400000).toISOString();

  const { data: bans } = await supabase
    .from("account_bans")
    .select("user_id")
    .is("reinstated_at", null)
    .eq("legal_hold", false)
    .is("purged_at", null)
    .not("user_id", "is", null)
    .lt("created_at", cutoff)
    .limit(50);

  let deleted = 0;
  let failed = 0;
  for (const ban of bans ?? []) {
    // An unanswered appeal means the person is still engaged: leave it alone.
    const { count: openAppeals } = await supabase
      .from("ban_reviews")
      .select("id", { count: "exact", head: true })
      .eq("user_id", ban.user_id)
      .is("resolved_at", null);
    if ((openAppeals ?? 0) > 0) continue;

    const result = await deleteAccountData(supabase, ban.user_id);
    if (!result.ok) {
      console.error("dormant-suspension delete failed:", ban.user_id, result.step, result.message);
      failed++;
      continue;
    }
    await supabase
      .from("account_bans")
      .update({ purged_at: new Date().toISOString() })
      .eq("user_id", ban.user_id)
      .is("reinstated_at", null);
    deleted++;
  }
  return { deleted, failed };
}

// Closes appeals that have waited longer than appeal_auto_deny_days (default 30,
// 0 = never) without a decision. Recorded as denied, with a note that says it
// was not reviewed in time (auto_closed: the app shows a fixed message saying so), so the usual 30-day
// wait before another appeal applies (submit-appeal enforces it from resolved_at).
// deno-lint-ignore no-explicit-any
async function closeStaleAppeals(supabase: any): Promise<{ closed: number }> {
  const { data: cfg } = await supabase
    .from("zz_config")
    .select("value")
    .eq("key", "appeal_auto_deny_days")
    .maybeSingle();
  const parsed = parseInt(cfg?.value ?? "", 10);
  const days = parsed >= 0 ? parsed : 30;
  if (days === 0) return { closed: 0 };

  const cutoff = new Date(Date.now() - days * 86400000).toISOString();
  const { data: closed, error } = await supabase
    .from("ban_reviews")
    .update({
      resolved_at: new Date().toISOString(),
      outcome: "denied",
      resolution: "Auto-closed: not reviewed within " + days + " days.",
      auto_closed: true,
    })
    .is("resolved_at", null)
    .lt("created_at", cutoff)
    .select("id");
  if (error) {
    console.error("close stale appeals error:", error.message);
    return { closed: 0 };
  }
  return { closed: (closed ?? []).length };
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
