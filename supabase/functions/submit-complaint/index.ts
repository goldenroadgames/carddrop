import { createClient } from "jsr:@supabase/supabase-js@2";
import { addressHash } from "../_shared/addressKey.ts";
import { sendEmail } from "../_shared/resend.ts";

// Called from the public /card/[id]/report web page (anon key, no login).
// Records a complaint against a card and its sender, blocks the sender from
// mailing the address(es) on that card (and every sender, if block_all),
// warns the sender at strikes 1 and 2, and bans account + device at the
// threshold. Always answers {status:"ok"} for well-formed requests so the
// page leaks nothing about cards, senders or the strike count.

// Orders that were (or are about to be) mailed.
const MAILED_STATUSES = ["paid", "submitted_to_lob", "printed", "mailed", "delivered"];

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
      .select("id, block_all")
      .eq("card_id", card.id)
      .maybeSingle();

    if (existing) {
      if (blockAll && !existing.block_all && mailed) {
        await supabase.from("card_complaints").update({ block_all: true }).eq("id", existing.id);
        await writeBlocks(supabase, orders ?? [], null);
      }
      return json({ status: "ok" });
    }

    const { error: insertError } = await supabase.from("card_complaints").insert({
      card_id:        card.id,
      sender_id:      card.sender_id,
      device_uuid:    card.device_uuid,
      complaint_text: text || null,
      block_all:      blockAll && mailed,
    });
    if (insertError) {
      // A concurrent duplicate report hits the unique card_id; that's fine.
      console.error("complaint insert error:", insertError);
      return json({ status: "ok" });
    }

    if (mailed) {
      await writeBlocks(supabase, orders ?? [], card.sender_id);
      if (blockAll) await writeBlocks(supabase, orders ?? [], null);
    }

    // ---------------- strikes ----------------
    const { data: cfgRows } = await supabase
      .from("zz_config")
      .select("key, value")
      .in("key", ["complaint_strikes_to_ban", "complaint_window_days"]);
    const cfg: Record<string, number> = {};
    for (const r of cfgRows ?? []) cfg[r.key] = parseInt(r.value, 10);
    const threshold = cfg["complaint_strikes_to_ban"] || 3;
    const windowDays = cfg["complaint_window_days"] || 180;
    const since = new Date(Date.now() - windowDays * 86400000).toISOString();

    const byAccount = card.sender_id ? await countComplaints(supabase, "sender_id", card.sender_id, since) : 0;
    const byDevice  = card.device_uuid ? await countComplaints(supabase, "device_uuid", card.device_uuid, since) : 0;
    const strikes = Math.max(byAccount, byDevice);

    if (strikes >= threshold) {
      if (card.sender_id) {
        await supabase.rpc("ban_account", {
          p_user_id: card.sender_id,
          p_reason: "repeated recipient complaints",
        });
      }
      if (card.device_uuid) {
        await supabase.from("user_devices").upsert(
          {
            device_uuid: card.device_uuid,
            banned: true,
            banned_at: new Date().toISOString(),
            ban_reason: "repeated recipient complaints",
          },
          { onConflict: "device_uuid" },
        );
      }
      await notifySender(supabase, card.sender_id, "ban",
        "Your CardDrop account has been suspended after repeated reports from recipients. " +
        "If you have questions, contact support@goldenroadgames.com.");
    } else {
      const when = card.sent_at ? new Date(card.sent_at).toLocaleDateString("en-US") : "recently";
      await notifySender(supabase, card.sender_id, "warning",
        `A recipient reported a card you sent (sent ${when}). ` +
        (mailed ? "You can no longer mail postcards to the address on that card. " : "") +
        "Repeated reports can lead to your account being suspended.");
    }

    return json({ status: "ok" });
  } catch (err) {
    console.error("submit-complaint error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

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

// In-app notice for everyone, email too when the account has an address.
async function notifySender(
  supabase: ReturnType<typeof createClient>,
  senderID: string | null,
  kind: "warning" | "ban",
  message: string,
) {
  if (!senderID) return;
  await supabase.from("user_notices").insert({ user_id: senderID, kind, message });

  const { data } = await supabase.auth.admin.getUserById(senderID);
  const email = data?.user?.email;
  if (email) {
    await sendEmail(
      email,
      kind === "ban" ? "Your CardDrop account has been suspended" : "A card you sent was reported",
      `${message}\n\n— CardDrop`,
    );
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}
