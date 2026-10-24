import { createClient } from "jsr:@supabase/supabase-js@2";
import { addressHash } from "../_shared/addressKey.ts";
import { sendEmail } from "../_shared/resend.ts";
import { syncCardFiles } from "../_shared/cardFiles.ts";

// Called from the public /card/[id]/report web page (anon key, no login).
// Records a complaint against a card and its sender, blocks the sender from
// mailing the address(es) on that card (and every sender, if block_all),
// warns the sender at strikes 1 and 2, and bans account + device at the
// threshold. Always answers {status:"ok"} for well-formed requests so the
// page leaks nothing about cards, senders or the strike count.

// Orders that were (or are about to be) mailed.
const MAILED_STATUSES = ["paid", "submitted_to_lob", "printed", "mailed", "delivered"];

type Minor = "yes" | "no" | "not_sure";
const MINOR_RANK: Record<Minor, number> = { no: 0, not_sure: 1, yes: 2 };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const body = await req.json().catch(() => ({}));
    const cardID = typeof body.cardID === "string" ? body.cardID.toLowerCase() : "";
    const blockAll = body.blockAll === true;
    const text = typeof body.text === "string" ? body.text.trim().slice(0, 2000) : "";
    if (!UUID_RE.test(cardID)) return json({ error: "invalid card" }, 400);

    // ---------------- per-IP rate limit ----------------
    // The admin "Report card" button calls this with the service-role key and
    // is exempt (it comes from the web server's IP, not a reporter's).
    const isAdminCall = req.headers.get("authorization") === `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`;
    if (!isAdminCall) {
      const ipHash = await hashIp(req);
      const limit = await attemptsPerHour(supabase);
      const since = new Date(Date.now() - 3600_000).toISOString();
      const { count, error: countError } = await supabase
        .from("report_attempts")
        .select("id", { count: "exact", head: true })
        .eq("ip_hash", ipHash)
        .gte("created_at", since);
      if (countError) {
        console.error("report_attempts count error:", countError);
        return json({ error: "try_later" }, 503);
      }
      if ((count ?? 0) >= limit) return json({ error: "rate_limited" }, 429);
      await supabase.from("report_attempts").insert({ ip_hash: ipHash });
    }
    // Optional contact, kept only with a yes / not sure answer.
    const contactRaw = typeof body.contact === "string" ? body.contact.trim().slice(0, 200) : "";
    // "Does this card show or involve a child?" yes / no / not_sure (null = not asked).
    const minor: Minor | null = body.involvesMinor === "yes" || body.involvesMinor === "no" || body.involvesMinor === "not_sure"
      ? body.involvesMinor : null;

    const { data: card } = await supabase
      .from("cards")
      .select("id, sender_id, device_uuid, sent_at")
      .eq("id", cardID)
      .maybeSingle();
    if (!card) return json({ status: "ok" });

    const { data: orders } = await supabase
      .from("physical_orders")
      .select("recipient_street, recipient_zip")
      .eq("card_id", card.id)
      .in("status", MAILED_STATUSES);
    const mailed = (orders ?? []).length > 0;

    // Already reported? Only an upgrade to "block all senders" does anything.
    const { data: existing } = await supabase
      .from("card_complaints")
      .select("id, block_all, involves_minor, decision")
      .eq("card_id", card.id)
      .maybeSingle();

    if (existing) {
      // Every repeat is counted (no strike): shown on the admin review pages.
      await supabase.rpc("bump_complaint_report", { p_card_id: card.id });
      // A card whose report was dismissed gets reported again: reopen the
      // same complaint (it counts as a strike again and returns to the review
      // list as unviewed), keeping the earlier history in card_view_log.
      if (existing.decision === "dismissed") {
        await supabase
          .from("card_complaints")
          .update({
            decision: null, decided_at: null, decided_by: null, cleared_at: null, first_viewed_at: null,
            involves_minor: minor,
          })
          .eq("id", existing.id);
        await sendEmail(
          Deno.env.get("ADMIN_ALERT_EMAIL") ?? "support@carddropapp.com",
          (minor === "yes" || minor === "not_sure" ? "URGENT (child involved?) — " : "") + "CardDrop: dismissed report reopened",
          `A card whose report you dismissed (${card.id}) was reported again.\n\nReview it: https://carddropapp.com/grg_admin/reported-cards`,
        );
        if (minor === "yes" || minor === "not_sure") await holdForChild(supabase, card.id, card.sender_id);
      }
      // A later report can only raise the child answer (yes > not sure > no),
      // and a raise to yes / not sure sends the owner an urgent email.
      if (minor && MINOR_RANK[minor] > MINOR_RANK[(existing.involves_minor as Minor | null) ?? "no"]) {
        await supabase
          .from("card_complaints")
          .update({ involves_minor: minor, ...(minor !== "no" && contactRaw ? { reporter_contact: contactRaw } : {}) })
          .eq("id", existing.id);
        if (minor !== "no") {
          await holdForChild(supabase, card.id, card.sender_id);
          await sendMinorAlert(card.id, minor);
        }
      }
      // Make sure the card is hidden even if this complaint predates the
      // reported_at column (idempotent: only stamps when still null).
      await supabase
        .from("cards")
        .update({ reported_at: new Date().toISOString() })
        .eq("id", card.id)
        .is("reported_at", null);
      await secureFiles(supabase, card.id);
      if (blockAll && !existing.block_all && mailed) {
        await supabase.from("card_complaints").update({ block_all: true }).eq("id", existing.id);
        await writeBlocks(supabase, orders ?? [], null);
      }
      return json({ status: "ok" });
    }

    // The sender's email, kept with the complaint for 12 months even if the
    // account is later deleted (null for anonymous senders).
    let senderEmail: string | null = null;
    if (card.sender_id) {
      const { data: senderUser } = await supabase.auth.admin.getUserById(card.sender_id);
      senderEmail = senderUser?.user?.email?.toLowerCase() ?? null;
    }

    const { error: insertError } = await supabase.from("card_complaints").insert({
      card_id:        card.id,
      sender_id:      card.sender_id,
      sender_email:   senderEmail,
      device_uuid:    card.device_uuid,
      complaint_text: text || null,
      block_all:      blockAll && mailed,
      involves_minor: minor,
      reporter_contact: (minor === "yes" || minor === "not_sure") && contactRaw ? contactRaw : null,
    });
    if (insertError) {
      // A concurrent duplicate report hits the unique card_id; that's fine.
      console.error("complaint insert error:", insertError);
      return json({ status: "ok" });
    }

    // Hide the card everywhere (web page, sender's app) and lock it from
    // delete / resend. Idempotent: only the first report stamps it.
    await supabase
      .from("cards")
      .update({ reported_at: new Date().toISOString() })
      .eq("id", card.id)
      .is("reported_at", null);

    // A report that says a child is (or may be) involved puts the card on
    // legal hold straight away, so it can never be deleted before review.
    if (minor === "yes" || minor === "not_sure") await holdForChild(supabase, card.id, card.sender_id);

    // The card is hidden now; move its image files out of public storage too.
    await secureFiles(supabase, card.id);

    if (mailed) {
      await writeBlocks(supabase, orders ?? [], card.sender_id);
      if (blockAll) await writeBlocks(supabase, orders ?? [], null);
    }

    // ---------------- strikes ----------------
    const { data: cfgRows } = await supabase
      .from("zz_config")
      .select("key, value")
      .in("key", ["complaint_strikes_to_ban", "complaint_window_days", "complaint_rapid_final_hours"]);
    const cfg: Record<string, number> = {};
    for (const r of cfgRows ?? []) cfg[r.key] = parseInt(r.value, 10);
    const threshold = cfg["complaint_strikes_to_ban"] || 3;
    const windowDays = cfg["complaint_window_days"] || 180;
    // Rapid strike-out: the 3 counted reports within this many hours = final (0 = off).
    const rapidHours = Number.isNaN(cfg["complaint_rapid_final_hours"]) || cfg["complaint_rapid_final_hours"] === undefined
      ? 72
      : cfg["complaint_rapid_final_hours"];
    const since = new Date(Date.now() - windowDays * 86400000).toISOString();

    const byAccount = card.sender_id ? await countComplaints(supabase, "sender_id", card.sender_id, since) : 0;
    const byDevice  = card.device_uuid ? await countComplaints(supabase, "device_uuid", card.device_uuid, since) : 0;
    const strikes = Math.max(byAccount, byDevice);

    if (strikes >= threshold) {
      // Say so in the ban reason when any counted complaint answered yes / not
      // sure to "does this card involve a child?".
      const childFlagged =
        (card.sender_id && (await countChildFlagged(supabase, "sender_id", card.sender_id, since)) > 0) ||
        (card.device_uuid && (await countChildFlagged(supabase, "device_uuid", card.device_uuid, since)) > 0);
      const banReason = childFlagged ? "repeated recipient complaints (child flagged)" : "repeated recipient complaints";
      if (card.sender_id) {
        await supabase.rpc("ban_account", {
          p_user_id: card.sender_id,
          p_reason: banReason,
        });
      }
      if (card.device_uuid) {
        await supabase.from("user_devices").upsert(
          {
            device_uuid: card.device_uuid,
            banned: true,
            banned_at: new Date().toISOString(),
            ban_reason: banReason,
          },
          { onConflict: "device_uuid" },
        );
      }
      // The three reports that did it all landed within rapidHours: make it final.
      const hitColumn: "sender_id" | "device_uuid" = byAccount >= threshold ? "sender_id" : "device_uuid";
      const hitValue = hitColumn === "sender_id" ? card.sender_id : card.device_uuid;
      if (rapidHours > 0 && hitValue && await withinHours(supabase, hitColumn, hitValue, since, threshold, rapidHours)) {
        const finalReason = `${threshold} reported cards within ${rapidHours} hours`;
        if (card.sender_id) {
          await supabase
            .from("account_bans")
            .update({ final: true, final_reason: finalReason })
            .eq("user_id", card.sender_id)
            .is("reinstated_at", null);
          await supabase.from("user_devices").update({ permanent: true }).eq("user_id", card.sender_id);
        }
        if (card.device_uuid) {
          await supabase.from("user_devices").update({ permanent: true }).eq("device_uuid", card.device_uuid);
        }
        await sendEmail(
          Deno.env.get("ADMIN_ALERT_EMAIL") ?? "support@carddropapp.com",
          "CardDrop: account suspended as FINAL (rapid strike-out)",
          `${finalReason}. The account (${card.sender_id ?? "no account"}) was suspended as final, with no appeal. ` +
            "You can still reinstate it from the Suspended Accounts page.\n\nReview it: https://carddropapp.com/grg_admin/suspended?seg=final",
        );
      }
      await notifySender(supabase, card.sender_id, "ban",
        "Your CardDrop account has been suspended after repeated reports from recipients. " +
        "If you have questions, contact support@carddropapp.com.");
    } else {
      const when = card.sent_at ? new Date(card.sent_at).toLocaleDateString("en-US") : "recently";
      await notifySender(supabase, card.sender_id, "warning",
        `A recipient reported a card you sent (sent ${when}). ` +
        (mailed ? "You can no longer mail postcards to the address on that card. " : "") +
        "Repeated reports can lead to your account being suspended.");
    }

    // Heads-up to the owner for every NEW reported card (repeat reports on the
    // same card returned earlier). Goes to ADMIN_ALERT_EMAIL, else support.
    await sendEmail(
      Deno.env.get("ADMIN_ALERT_EMAIL") ?? "support@carddropapp.com",
      (minor === "yes" || minor === "not_sure" ? "URGENT (child involved?) — " : "") +
        (strikes >= threshold ? "CardDrop: card reported, account suspended" : "CardDrop: card reported"),
      [
        `A card was reported (${mailed ? "mailed" : "digital"}).`,
        ...((minor === "yes" || minor === "not_sure") && contactRaw ? [`Reporter left contact: ${contactRaw}`] : []),
        ...(minor ? [`Reporter says a child is involved: ${minor === "not_sure" ? "NOT SURE" : minor.toUpperCase()}.`] : []),
        `Strikes on this sender: ${strikes} of ${threshold}${strikes >= threshold ? " (account auto-suspended)" : ""}.`,
        senderEmail ? `Sender: ${senderEmail}` : "Sender: no email (anonymous account)",
        ...(blockAll ? ["The reporter asked to block all senders from their address."] : []),
        text ? `Reporter wrote: ${text.slice(0, 500)}` : "No complaint text.",
        "",
        "Review it: https://carddropapp.com/grg_admin/reported-cards",
      ].join("\n"),
    );

    return json({ status: "ok" });
  } catch (err) {
    console.error("submit-complaint error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

async function countChildFlagged(
  supabase: ReturnType<typeof createClient>,
  column: "sender_id" | "device_uuid",
  value: string,
  since: string,
): Promise<number> {
  const { count } = await supabase
    .from("card_complaints")
    .select("id", { count: "exact", head: true })
    .eq(column, value)
    .is("cleared_at", null)
    .in("involves_minor", ["yes", "not_sure"])
    .gte("created_at", since);
  return count ?? 0;
}

// Legal hold on the card (cards.legal_hold: the sweeper, the sender and account
// deletion all leave it alone). Only stamps a card that is not already held, and
// writes a 'hold' line to card_view_log. An admin can still release it.
async function holdForChild(
  supabase: ReturnType<typeof createClient>,
  cardID: string,
  senderID: string | null,
) {
  const { data: held, error } = await supabase
    .from("cards")
    .update({ legal_hold: true, legal_hold_at: new Date().toISOString() })
    .eq("id", cardID)
    .eq("legal_hold", false)
    .select("id");
  if (error) {
    console.error("child-report legal hold error:", error);
    return;
  }
  if ((held ?? []).length === 0) return;
  await supabase.from("card_view_log").insert({
    card_id: cardID,
    sender_id: senderID,
    event: "hold",
    reason: "Automatic: report says a child may be involved",
    viewed_by: "system",
  });
}

async function sendMinorAlert(cardID: string, minor: Minor) {
  await sendEmail(
    Deno.env.get("ADMIN_ALERT_EMAIL") ?? "support@carddropapp.com",
    "URGENT (child involved?) — CardDrop: report updated",
    [
      `A later report on an already-reported card (${cardID}) now says a child is involved: ${minor === "not_sure" ? "NOT SURE" : "YES"}.`,
      "",
      "Review it: https://carddropapp.com/grg_admin/reported-cards",
    ].join("\n"),
  );
}

async function countComplaints(
  supabase: ReturnType<typeof createClient>,
  column: "sender_id" | "device_uuid",
  value: string,
  since: string,
): Promise<number> {
  const { count } = await supabase
    .from("card_complaints")
    .select("id", { count: "exact", head: true })
    .eq(column, value)
    .is("cleared_at", null)
    .gte("created_at", since);
  return count ?? 0;
}

// Inserts one block per distinct address (senderID null = every sender).
// Duplicates hit the unique index and are ignored.
async function writeBlocks(
  supabase: ReturnType<typeof createClient>,
  orders: { recipient_street: string | null; recipient_zip: string | null }[],
  senderID: string | null,
) {
  const seen = new Set<string>();
  for (const o of orders) {
    const hash = await addressHash(o.recipient_street, o.recipient_zip);
    if (!hash || seen.has(hash)) continue;
    seen.add(hash);
    const { error } = await supabase.from("mail_blocks").insert({ sender_id: senderID, address_hash: hash });
    if (error && error.code !== "23505") console.error("mail_blocks insert error:", error);
  }
}

// In-app notice only: the sender learns about a report from the app, never by
// email. (Emails in this function go to the owner, not to users.)
async function notifySender(
  supabase: ReturnType<typeof createClient>,
  senderID: string | null,
  kind: "warning" | "ban",
  message: string,
) {
  if (!senderID) return;
  await supabase.from("user_notices").insert({ user_id: senderID, kind, message });
}

// Keyed hash of the visitor's IP, so the table never holds a raw address.
// cf-connecting-ip is set by Cloudflare in front of Supabase and can't be
// forged by the caller; the other headers are fallbacks.
async function hashIp(req: Request): Promise<string> {
  const ip = req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-real-ip") ??
    req.headers.get("x-forwarded-for")?.split(",")[0].trim() ??
    "unknown";
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(ip)));
  return Array.from(sig, (b) => b.toString(16).padStart(2, "0")).join("");
}

// deno-lint-ignore no-explicit-any
async function attemptsPerHour(supabase: any): Promise<number> {
  const { data } = await supabase
    .from("zz_config")
    .select("value")
    .eq("key", "report_attempts_per_ip_hourly")
    .maybeSingle();
  const n = parseInt(data?.value ?? "", 10);
  return n > 0 ? n : 3;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}


// Move the reported card's files to private storage. A failure is logged and
// the owner is emailed; the card stays hidden regardless, and the nightly sweep
// retries every reported or held card whose files are still public.
async function secureFiles(supabase: ReturnType<typeof createClient>, cardID: string) {
  const err = await syncCardFiles(supabase, cardID);
  if (!err) return;
  console.error("secure files failed:", cardID, err);
  await sendEmail(
    Deno.env.get("ADMIN_ALERT_EMAIL") ?? "support@carddropapp.com",
    "CardDrop: could not move a reported card's files to private storage",
    `Card ${cardID} is hidden, but moving its image files to private storage failed:\n${err}\n\nThe nightly sweep will retry.`,
  );
}


// True when the most recent `count` standing (not cleared) reports for this
// account or device, inside the report window, all fall within `hours` of each
// other. Needs `count` reports; fewer returns false.
async function withinHours(
  supabase: ReturnType<typeof createClient>,
  column: "sender_id" | "device_uuid",
  value: string,
  since: string,
  count: number,
  hours: number,
): Promise<boolean> {
  const { data } = await supabase
    .from("card_complaints")
    .select("created_at")
    .eq(column, value)
    .is("cleared_at", null)
    .gte("created_at", since)
    .order("created_at", { ascending: false })
    .limit(count);
  const times = (data ?? []).map((r: { created_at: string }) => Date.parse(r.created_at));
  if (times.length < count) return false;
  return Math.max(...times) - Math.min(...times) <= hours * 3600_000;
}
