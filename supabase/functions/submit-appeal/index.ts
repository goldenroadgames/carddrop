import { createClient } from "jsr:@supabase/supabase-js@2";
import { isBanned } from "../_shared/bans.ts";
import { sendEmail } from "../_shared/resend.ts";

// A suspended user's appeal, sent from the "Account Suspended" screen.
// Body: { message: string (1-1000 chars), deviceUUID: string }, or
// { check: true, deviceUUID } which only answers {canAppeal: boolean} so the app
// can hide the Appeal button on a final suspension.
// An account reinstated appeal_max_reinstatements times already (zz_config,
// default 2; counted by account and by verified email) gets no more appeals:
// {error:"no_appeals"}.
// Saves a row in ban_reviews (service role: clients cannot write that table),
// one open appeal per user, and a denied user can appeal again after
// COOLDOWN_DAYS. Emails APPEAL_NOTIFY_EMAIL (default support@carddropapp.com)
// that an appeal is waiting on /grg_admin/appeals; the message itself is not
// emailed. The app shows the outcome by reading its own ban_reviews row.
// Replies: {status:"ok"|"already_open"} or {error: invalid | not_suspended |
// cooldown (with retryAfter) | no_appeals | try_later}.
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_MESSAGE = 1000;
const COOLDOWN_DAYS = 30;
const DEFAULT_MAX_REINSTATEMENTS = 2;

Deno.serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "unauthorized" }, 401);
    const jwt = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(jwt);
    if (authError || !user) return json({ error: "unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    const message = typeof body.message === "string" ? body.message.trim() : "";
    const deviceUUID = typeof body.deviceUUID === "string" ? body.deviceUUID : "";
    const checkOnly = body.check === true;
    if (!UUID_RE.test(deviceUUID) || (!checkOnly && (!message || message.length > MAX_MESSAGE))) {
      return json({ error: "invalid" }, 400);
    }

    // Only a suspended caller can appeal (same ban test as send-card).
    const isVerified = (user.app_metadata?.send_unlocked === true && !!user.email_confirmed_at) ||
      (user.identities ?? []).some((i: { provider: string }) => i.provider === "apple");
    if (!(await isBanned(supabase, user, isVerified, deviceUUID))) {
      return json({ error: "not_suspended" }, 403);
    }

    // Repeat offenders: once an account has been reinstated the allowed number
    // of times, a new suspension is final and no appeal is offered or accepted.
    const { data: limitRow } = await supabase
      .from("zz_config")
      .select("value")
      .eq("key", "appeal_max_reinstatements")
      .maybeSingle();
    const parsedLimit = parseInt(limitRow?.value ?? "", 10);
    const maxReinstatements = parsedLimit >= 0 ? parsedLimit : DEFAULT_MAX_REINSTATEMENTS;
    const emailFilter = isVerified && user.email ? `,email.eq.${user.email.toLowerCase()}` : "";
    const { count: reinstated } = await supabase
      .from("account_bans")
      .select("id", { count: "exact", head: true })
      .not("reinstated_at", "is", null)
      .or(`user_id.eq.${user.id}${emailFilter}`);
    // An admin can also mark the current suspension final by hand.
    const { count: markedFinal } = await supabase
      .from("account_bans")
      .select("id", { count: "exact", head: true })
      .is("reinstated_at", null)
      .eq("final", true)
      .or(`user_id.eq.${user.id}${emailFilter}`);
    const canAppeal = (reinstated ?? 0) < maxReinstatements && (markedFinal ?? 0) === 0;
    if (checkOnly) return json({ canAppeal });
    if (!canAppeal) return json({ error: "no_appeals" }, 403);

    const { data: open } = await supabase
      .from("ban_reviews")
      .select("id")
      .eq("user_id", user.id)
      .is("resolved_at", null)
      .maybeSingle();
    if (open) return json({ status: "already_open" });

    const { data: lastDenied } = await supabase
      .from("ban_reviews")
      .select("resolved_at")
      .eq("user_id", user.id)
      .eq("outcome", "denied")
      .order("resolved_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (lastDenied?.resolved_at) {
      const retryAfter = new Date(new Date(lastDenied.resolved_at).getTime() + COOLDOWN_DAYS * 86400000);
      if (retryAfter.getTime() > Date.now()) {
        return json({ error: "cooldown", retryAfter: retryAfter.toISOString() }, 429);
      }
    }

    // ban_reviews.device_uuid references user_devices (which references users).
    await supabase.from("users").upsert({ id: user.id }, { onConflict: "id", ignoreDuplicates: true });
    await supabase
      .from("user_devices")
      .upsert({ device_uuid: deviceUUID, user_id: user.id }, { onConflict: "device_uuid", ignoreDuplicates: true });

    const { error: insertError } = await supabase.from("ban_reviews").insert({
      device_uuid: deviceUUID,
      user_id: user.id,
      message,
    });
    if (insertError) {
      if (insertError.code === "23505") return json({ status: "already_open" }); // one open appeal per user
      console.error("ban_reviews insert error:", insertError.code, insertError.message);
      return json({ error: "try_later" }, 500);
    }

    await sendEmail(
      Deno.env.get("APPEAL_NOTIFY_EMAIL") ?? "support@carddropapp.com",
      "New CardDrop suspension appeal",
      "A suspension appeal is waiting for review:\nhttps://carddropapp.com/grg_admin/appeals\n\nAccount: " + user.id,
    );

    return json({ status: "ok" });
  } catch (err) {
    console.error("submit-appeal error:", err);
    return json({ error: "try_later" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
