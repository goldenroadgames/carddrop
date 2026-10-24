import { createClient } from "jsr:@supabase/supabase-js@2";
import { purgeCard } from "../_shared/purgeCard.ts";
import { deleteCard } from "../_shared/deleteCard.ts";
import { deleteAccountData } from "../_shared/deleteAccount.ts";
import { secureCardFiles } from "../_shared/cardFiles.ts";

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
      .eq("legal_hold", false)
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

    // ---------------- retention (retention_days, default 365) ----------------
    // Complaint text, order name/address snapshots, the digital send log,
    // moderation block records and reported cards are kept retention_days
    // (zz_config). Financial columns on orders are kept (7 years).
    const { data: retentionRow } = await supabase
      .from("zz_config")
      .select("value")
      .eq("key", "retention_days")
      .maybeSingle();
    const retentionDays = parseInt(retentionRow?.value ?? "", 10);
    const cutoff = new Date(Date.now() - (retentionDays > 0 ? retentionDays : 365) * 86400000).toISOString();
    // Cards on legal hold keep their complaint text, send log and order
    // snapshots too.
    const { data: heldRows } = await supabase.from("cards").select("id").eq("legal_hold", true);
    const heldList = `(${(heldRows ?? []).map((c: { id: string }) => c.id).join(",")})`;
    // deno-lint-ignore no-explicit-any
    const notHeld = (q: any) => ((heldRows ?? []).length > 0 ? q.not("card_id", "in", heldList) : q);
    const retention: Record<string, string | null> = {};
    const steps: [string, PromiseLike<{ error: { message: string } | null }>][] = [
      ["complaint_text", notHeld(supabase.from("card_complaints")
        .update({ complaint_text: null, sender_email: null, reporter_contact: null }).lt("created_at", cutoff)
        .or("complaint_text.not.is.null,sender_email.not.is.null,reporter_contact.not.is.null"))],
      ["order_snapshots", notHeld(supabase.from("physical_orders").update({
        recipient_first_name: null, recipient_last_name: null, recipient_street: null,
        recipient_city: null, recipient_state: null, recipient_zip: null, recipient_country: null,
        sender_first_name: null, sender_last_name: null, sender_street: null,
        sender_city: null, sender_state: null, sender_zip: null, sender_country: null,
        scrubbed_at: new Date().toISOString(),
      }).lt("created_at", cutoff).is("scrubbed_at", null))],
      ["send_log", notHeld(supabase.from("card_recipients").delete().lt("created_at", cutoff))],
      // Records of content blocked by moderation (no content, just who/kind/category/time).
      ["content_blocks", supabase.from("content_blocks").delete().lt("created_at", cutoff)],
      // Send-rate cap log: the cap only looks back 24 hours, so keep 2 days.
      ["send_events", supabase.from("send_events").delete()
        .lt("created_at", new Date(Date.now() - 2 * 86400000).toISOString())],
      // Report-form rate limit log (hashed IPs): the limit only looks back an hour.
      ["report_attempts", supabase.from("report_attempts").delete()
        .lt("created_at", new Date(Date.now() - 2 * 86400000).toISOString())],
    ];
    for (const [name, op] of steps) {
      const { error: opError } = await op;
      retention[name] = opError ? opError.message : null;
      if (opError) console.error("sweep retention error:", name, opError.message);
    }

    // Staged uploads that never became a card (private card-staging bucket).
    const staging = await sweepStaging(supabase, 2 * 86400000);

    // Reported cards are kept as evidence for retention_days, then deleted like
    // any other card (blanked tombstone + files purged).
    const { data: expiredReports } = await supabase
      .from("cards")
      .select("id, sender_id, deleted_at")
      .not("reported_at", "is", null)
      .lt("reported_at", cutoff)
      .is("deleted_at", null)
      .eq("legal_hold", false)
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

    // "Delete data now" requests from the admin page.
    const deleteRequests = await sweepDeleteRequests(supabase);

    // Ended history (review log, report records, reinstated suspensions and
    // their resolved appeals) after history_retention_days, unless held or the
    // sender is still suspended.
    const history = await sweepHistory(supabase);

    // Self-healing: any reported or held card whose image files are still in
    // the public bucket (a move that failed, or a card from before the move
    // existed) is moved to private storage now.
    const secured = await sweepHeldFiles(supabase);

    // Moderation categories: add zz_config rows for any category OpenAI has
    // added since the last run. Never stops the sweep.
    let newCategories: string[] | { error: string } = [];
    try {
      newCategories = await sweepModerationCategories(supabase);
    } catch (err) {
      console.error("moderation category check failed:", err);
      newCategories = { error: String(err) };
    }

    // Marketing copies of people who were kicked off (final suspension, or the
    // account's data already deleted after a long unappealed suspension). Never
    // stops the sweep.
    let marketingRemoved: { removed: number; failed: number } | { error: string };
    try {
      marketingRemoved = await sweepMarketingOfSuspended(supabase);
    } catch (err) {
      console.error("marketing removal failed:", err);
      marketingRemoved = { error: String(err) };
    }

    return json({ staging, purged, failed, reportedDeleted, retention, finalSuspensions, staleAppeals, dormantSuspensions, deleteRequests, history, secured, newCategories, marketingRemoved });
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

// Suspensions where the admin pressed "Delete data now" (delete_requested_at set):
// deleted on this run, final or not, unless there is a legal hold. The ban rows
// stay; purged_at stops a repeat.
// deno-lint-ignore no-explicit-any
async function sweepDeleteRequests(supabase: any): Promise<{ deleted: number; failed: number }> {
  const { data: bans } = await supabase
    .from("account_bans")
    .select("user_id")
    .is("reinstated_at", null)
    .eq("legal_hold", false)
    .is("purged_at", null)
    .not("delete_requested_at", "is", null)
    .not("user_id", "is", null)
    .limit(50);

  let deleted = 0;
  let failed = 0;
  for (const ban of bans ?? []) {
    const result = await deleteAccountData(supabase, ban.user_id);
    if (!result.ok) {
      console.error("requested delete failed:", ban.user_id, result.step, result.message);
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

// Removes files in card-staging older than maxAgeMs. Staged files are normally
// moved out within seconds of a send; leftovers come from abandoned or failed
// sends. Walks {userId}/ folders; capped so one run stays small.
async function sweepStaging(supabase: ReturnType<typeof createClient>, maxAgeMs: number): Promise<string | number> {
  const cutoff = Date.now() - maxAgeMs;
  let removed = 0;
  for (let offset = 0; offset < 2000; offset += 100) {
    const { data: folders, error } = await supabase.storage.from("card-staging").list("", { limit: 100, offset });
    if (error) return `list: ${error.message}`;
    if (!folders || folders.length === 0) break;
    for (const f of folders) {
      if (f.id !== null) continue; // only user folders
      const { data: files, error: fileError } = await supabase.storage.from("card-staging").list(f.name, { limit: 1000 });
      if (fileError) return `list ${f.name}: ${fileError.message}`;
      const old = (files ?? [])
        .filter((o) => o.id !== null && o.created_at && new Date(o.created_at).getTime() < cutoff)
        .map((o) => `${f.name}/${o.name}`);
      if (old.length === 0) continue;
      const { error: rmError } = await supabase.storage.from("card-staging").remove(old);
      if (rmError) return `remove ${f.name}: ${rmError.message}`;
      removed += old.length;
    }
    if (folders.length < 100) break;
  }
  return removed;
}

// Removes the marketing copies (public marketing-cards files + marketing_cards
// row, which also drops the card from the Inspire gallery and the landing
// carousel) of every sender who was kicked off: an active suspension that is
// FINAL (flagged final, or reinstated appeal_max_reinstatements times already)
// or whose account data was already deleted (purged_at set). A suspension that
// can still be appealed keeps its marketing cards. Files go first, so a failed
// run leaves the row and is retried tomorrow.
// deno-lint-ignore no-explicit-any
async function sweepMarketingOfSuspended(supabase: any): Promise<{ removed: number; failed: number }> {
  const { data: cfg } = await supabase.from("zz_config").select("value").eq("key", "appeal_max_reinstatements").maybeSingle();
  const parsed = parseInt(cfg?.value ?? "", 10);
  const maxReinstatements = parsed >= 0 ? parsed : 2;

  const { data: bans } = await supabase
    .from("account_bans")
    .select("user_id, email, final, purged_at")
    .is("reinstated_at", null)
    .not("user_id", "is", null)
    .limit(200);

  const kickedOut: string[] = [];
  for (const ban of bans ?? []) {
    let isFinal = !!ban.final || !!ban.purged_at;
    if (!isFinal) {
      const emailOk = ban.email && !/[,()]/.test(ban.email);
      const { count } = await supabase
        .from("account_bans")
        .select("id", { count: "exact", head: true })
        .not("reinstated_at", "is", null)
        .or(`user_id.eq.${ban.user_id}${emailOk ? `,email.eq.${ban.email}` : ""}`);
      isFinal = (count ?? 0) >= maxReinstatements;
    }
    if (isFinal) kickedOut.push(ban.user_id);
  }
  if (kickedOut.length === 0) return { removed: 0, failed: 0 };

  const { data: cards } = await supabase
    .from("marketing_cards")
    .select("card_id")
    .in("sender_id", kickedOut)
    .limit(100);

  let removed = 0;
  let failed = 0;
  for (const row of cards ?? []) {
    const id = row.card_id as string;
    const names = ["", "_thumb", "_full", "_before", "_before_full", "_before_thumb"].map((suffix) => `${id}${suffix}.jpg`);
    const { error: fileError } = await supabase.storage.from("marketing-cards").remove(names);
    if (fileError) {
      console.error("marketing file removal failed:", id, fileError.message);
      failed++;
      continue;
    }
    const { error: rowError } = await supabase.from("marketing_cards").delete().eq("card_id", id);
    if (rowError) {
      console.error("marketing row removal failed:", id, rowError.message);
      failed++;
      continue;
    }
    removed++;
  }
  return { removed, failed };
}

// Asks OpenAI's moderation endpoint about one harmless text, reads the category
// names in the reply, and inserts any missing moderation_threshold_<cat> ('0')
// and moderation_label_<cat> (raw name) rows. Returns the categories it added.
// deno-lint-ignore no-explicit-any
async function sweepModerationCategories(supabase: any): Promise<string[]> {
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) throw new Error("OPENAI_API_KEY is not set");
  const res = await fetch("https://api.openai.com/v1/moderations", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({ model: "omni-moderation-latest", input: "Happy birthday!" }),
  });
  if (!res.ok) throw new Error(`OpenAI moderation HTTP ${res.status}`);
  const body = await res.json();
  const categories = Object.keys(body?.results?.[0]?.categories ?? {});
  if (categories.length === 0) throw new Error("no categories in OpenAI reply");

  const { data: existing } = await supabase.from("zz_config").select("key").like("key", "moderation_%");
  const have = new Set((existing ?? []).map((r: { key: string }) => r.key));
  const rows: { key: string; value: string; description: string }[] = [];
  const added: string[] = [];
  for (const cat of categories) {
    let isNew = false;
    if (!have.has(`moderation_threshold_${cat}`)) {
      isNew = true;
      rows.push({
        key: `moderation_threshold_${cat}`,
        value: "0",
        description: `Minimum OpenAI moderation score for ${cat} to block (0.0-1.0). 0 = block on OpenAI's own flag alone (strictest). A higher value lets lower-scoring flags through; it can never block more than OpenAI's flag.`,
      });
    }
    if (!have.has(`moderation_label_${cat}`)) {
      isNew = true;
      rows.push({
        key: `moderation_label_${cat}`,
        value: cat,
        description: `Friendly name shown to the user and in admin when OpenAI flags ${cat}. Takes effect on the next moderation call, no redeploy.`,
      });
    }
    if (isNew) added.push(cat);
  }
  if (rows.length > 0) {
    const { error } = await supabase.from("zz_config").upsert(rows, { onConflict: "key", ignoreDuplicates: true });
    if (error) throw new Error(error.message);
  }
  return added;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}


// "Keep a record while it is still doing a job, otherwise delete it
// history_retention_days (default 730) after its last activity." Still doing a
// job: the card is on legal hold, the sender has an active suspension or an
// account hold, or the decision is "CSAM review required". Chosen in JS from
// short selects (not long filter strings) so empty lists and null columns
// can't silently keep or delete the wrong rows.
// deno-lint-ignore no-explicit-any
async function sweepHistory(supabase: any): Promise<Record<string, number | string>> {
  const { data: cfg } = await supabase
    .from("zz_config")
    .select("value")
    .eq("key", "history_retention_days")
    .maybeSingle();
  const days = parseInt(cfg?.value ?? "", 10);
  const cutoff = new Date(Date.now() - (days > 0 ? days : 730) * 86400000).toISOString();

  const { data: heldCards } = await supabase.from("cards").select("id").eq("legal_hold", true);
  const keepCards = new Set<string>((heldCards ?? []).map((c: { id: string }) => c.id));
  const { data: keepBans } = await supabase
    .from("account_bans")
    .select("user_id, reinstated_at, legal_hold")
    .or("reinstated_at.is.null,legal_hold.eq.true");
  const keepAccounts = new Set<string>(
    (keepBans ?? []).map((b: { user_id: string | null }) => b.user_id).filter(Boolean) as string[],
  );

  const result: Record<string, number | string> = {};
  const removeIds = async (table: string, ids: string[]) => {
    for (let i = 0; i < ids.length; i += 100) {
      const { error } = await supabase.from(table).delete().in("id", ids.slice(i, i + 100));
      if (error) {
        console.error("sweep history error:", table, error.message);
        return error.message as string;
      }
    }
    return null;
  };

  // Review log on cards.
  const { data: logRows } = await supabase
    .from("card_view_log")
    .select("id, card_id, sender_id, event, reason")
    .lt("created_at", cutoff)
    .limit(1000);
  // Recorded NCMEC / law-enforcement actions are never deleted (keep in step
  // with HOLD_ACTIONS in web/app/grg_admin/lib/actionTypes.ts).
  const PERMANENT_ACTIONS = new Set(["NCMEC report filed", "Law enforcement contacted"]);
  const logIds = (logRows ?? [])
    .filter((r: { card_id: string; sender_id: string | null; event: string; reason: string | null }) =>
      r.event !== "child_confirmed" &&
      !(r.event === "action" && r.reason && PERMANENT_ACTIONS.has(r.reason)) &&
      !keepCards.has(r.card_id) && !(r.sender_id && keepAccounts.has(r.sender_id)))
    .map((r: { id: string }) => r.id);
  result.card_view_log = (await removeIds("card_view_log", logIds)) ?? logIds.length;

  // Report records.
  const { data: complaintRows } = await supabase
    .from("card_complaints")
    .select("id, card_id, sender_id, decision")
    .lt("created_at", cutoff)
    .limit(1000);
  const complaintIds = (complaintRows ?? [])
    .filter((r: { card_id: string; sender_id: string | null; decision: string | null }) =>
      r.decision !== "child_confirmed" && !keepCards.has(r.card_id) && !(r.sender_id && keepAccounts.has(r.sender_id)))
    .map((r: { id: string }) => r.id);
  result.card_complaints = (await removeIds("card_complaints", complaintIds)) ?? complaintIds.length;

  // Reinstated suspensions (an active, final or held one is never touched).
  const { data: endedBans } = await supabase
    .from("account_bans")
    .select("id, user_id, legal_hold")
    .not("reinstated_at", "is", null)
    .lt("reinstated_at", cutoff)
    .limit(1000);
  const banIds = (endedBans ?? [])
    .filter((b: { user_id: string | null; legal_hold: boolean }) => !b.legal_hold && !(b.user_id && keepAccounts.has(b.user_id)))
    .map((b: { id: string }) => b.id);
  result.account_bans = (await removeIds("account_bans", banIds)) ?? banIds.length;

  // Resolved appeals of accounts that are not suspended now.
  const { data: oldAppeals } = await supabase
    .from("ban_reviews")
    .select("id, user_id")
    .not("resolved_at", "is", null)
    .lt("resolved_at", cutoff)
    .limit(1000);
  const appealIds = (oldAppeals ?? [])
    .filter((a: { user_id: string | null }) => !(a.user_id && keepAccounts.has(a.user_id)))
    .map((a: { id: string }) => a.id);
  result.ban_reviews = (await removeIds("ban_reviews", appealIds)) ?? appealIds.length;

  return result;
}


// Reported or legal-hold cards keep their image files in private storage.
// secureCardFiles does nothing for a card whose files are already there, so
// this is cheap to run every night over every such card.
// deno-lint-ignore no-explicit-any
async function sweepHeldFiles(supabase: any): Promise<{ checked: number; failed: number }> {
  const { data: cards } = await supabase
    .from("cards")
    .select("id, sender_id")
    .is("deleted_at", null)
    .not("sender_id", "is", null)
    .or("reported_at.not.is.null,legal_hold.eq.true")
    .limit(500);
  let failed = 0;
  for (const card of cards ?? []) {
    const err = await secureCardFiles(supabase, card.id, card.sender_id);
    if (err) {
      failed++;
      console.error("sweep secure files error:", card.id, err);
    }
  }
  return { checked: (cards ?? []).length, failed };
}
