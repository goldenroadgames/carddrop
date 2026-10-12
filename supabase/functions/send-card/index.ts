import { createClient } from "jsr:@supabase/supabase-js@2";
import { isBanned } from "../_shared/bans.ts";
import { moderateAndPromote } from "../_shared/cardImages.ts";
import { recordContentBlock } from "../_shared/contentBlocks.ts";
import { removeFolder } from "../_shared/purgeCard.ts";

Deno.serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Authenticate the caller via JWT in Authorization header.
    // supabase.functions.invoke() on iOS sends this automatically.
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "unauthorized" }, 401);

    const jwt = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(jwt);
    if (authError || !user) return json({ error: "unauthorized" }, 401);

    // Parse request body
    const { cardID, deviceUUID, senderNickname, recipientNickname,
            recipientFirstName, recipientLastName, recipientName,
            recipientPhone, recipientEmail, messagePreview,
            isPortrait, frontInkMessage, backInkMessage, designFeatures,
            extraTexts } = await req.json();

    if (!cardID)    return json({ error: "cardID required" }, 400);
    if (!deviceUUID) return json({ error: "deviceUUID required" }, 400);

    // A deleted card is a tombstone: re-sending it would refill the blanked
    // row (the upsert below) while deleted_at stays set.
    const { data: existingCard } = await supabase
      .from("cards")
      .select("deleted_at, reported_at, legal_hold")
      .eq("id", cardID)
      .maybeSingle();
    if (existingCard?.deleted_at) return json({ error: "card_deleted" }, 410);
    // A reported card is locked: no resending it.
    if (existingCard?.reported_at || existingCard?.legal_hold) return json({ error: "card_unavailable" }, 403);

    // ----------------------------------------------------------------
    // Ban check — account, verified email, or device (see _shared/bans.ts).
    // Bypasses RLS via service role.
    // ----------------------------------------------------------------
    const isVerified = isVerifiedUser(user);
    if (await isBanned(supabase, user, isVerified, deviceUUID)) {
      return json({ error: "suspended" }, 403);
    }

    // ----------------------------------------------------------------
    // Fetch user record
    // ----------------------------------------------------------------
    const { data: userRow } = await supabase
      .from("users")
      .select("sends_this_month, sends_lifetime")
      .eq("id", user.id)
      .maybeSingle();

    const sendsMonth    = userRow?.sends_this_month ?? 0;
    const sendsLifetime = userRow?.sends_lifetime   ?? 0;

    // ----------------------------------------------------------------
    // Determine effective tier
    // Priority: verified (OTP done / Apple) > unverified > anonymous.
    // users.tier is no longer used: there is no paid tier, and a client-writable
    // column must never grant anything.
    // ----------------------------------------------------------------
    const isAnonymous = user.is_anonymous ?? false;

    let tier: string;
    if (isVerified)              tier = "verified";
    else if (!isAnonymous)       tier = "unverified";  // has email but not OTP verified
    else                         tier = "anonymous";

    // ----------------------------------------------------------------
    // Fetch send limits from config table
    // ----------------------------------------------------------------
    const { data: configRows } = await supabase
      .from("zz_config")
      .select("key, value")
      .in("key", [
        `send_limit_${tier}_monthly`,
        `send_limit_${tier}_lifetime`,
      ]);

    const configMap: Record<string, number> = {};
    for (const row of configRows ?? []) {
      configMap[row.key] = parseInt(row.value, 10);
    }

    const monthlyLimit  = configMap[`send_limit_${tier}_monthly`]  ?? -1;
    const lifetimeLimit = configMap[`send_limit_${tier}_lifetime`] ?? -1;

    // ----------------------------------------------------------------
    // Enforce limits
    // ----------------------------------------------------------------
    if (monthlyLimit !== -1 && sendsMonth >= monthlyLimit) {
      return json({ error: "monthly_limit_reached", tier }, 429);
    }
    if (lifetimeLimit !== -1 && sendsLifetime >= lifetimeLimit) {
      return json({ error: "lifetime_limit_reached", tier }, 429);
    }

    // Device-level cap for anonymous/unverified: a new anonymous ID or account
    // on the same device doesn't reset the count. month_key lets the monthly
    // count reset itself.
    const monthKey = new Date().toISOString().slice(0, 7);
    const { data: deviceCounts } = await supabase
      .from("user_devices")
      .select("sends_this_month, sends_lifetime, month_key")
      .eq("device_uuid", deviceUUID)
      .maybeSingle();
    const deviceMonth    = deviceCounts?.month_key === monthKey ? (deviceCounts?.sends_this_month ?? 0) : 0;
    const deviceLifetime = deviceCounts?.sends_lifetime ?? 0;
    const deviceCapped   = tier === "anonymous" || tier === "unverified";
    if (deviceCapped) {
      if (monthlyLimit !== -1 && deviceMonth >= monthlyLimit) {
        return json({ error: "monthly_limit_reached", tier }, 429);
      }
      if (lifetimeLimit !== -1 && deviceLifetime >= lifetimeLimit) {
        return json({ error: "lifetime_limit_reached", tier }, 429);
      }
    }

    // ----------------------------------------------------------------
    // Send-rate cap: send-card calls per hour / per day, counted from
    // send_events (server-written, no foreign key to cards, so resending a
    // card counts again and deleting a card resets nothing). The same limits
    // apply to the account and to the device, whichever is reached first
    // (deviceUUID comes from the app, so the device cap is a backstop, not
    // proof of identity). Applies to every tier. Each call that gets past this
    // check is recorded, including ones the content gate later rejects.
    // ----------------------------------------------------------------
    {
      const { data: rateRows } = await supabase
        .from("zz_config")
        .select("key, value")
        .in("key", ["send_rate_hourly", "send_rate_daily", "send_rate_device_hourly", "send_rate_device_daily"]);
      const rate: Record<string, number> = {};
      for (const row of rateRows ?? []) rate[row.key] = parseInt(row.value, 10);
      const hourlyCap = rate["send_rate_hourly"] ?? 10;
      const dailyCap  = rate["send_rate_daily"]  ?? 50;
      // Device caps have their own settings; unset, they match the account caps.
      const deviceHourlyCap = rate["send_rate_device_hourly"] ?? hourlyCap;
      const deviceDailyCap  = rate["send_rate_device_daily"]  ?? dailyCap;

      const countSince = async (column: "user_id" | "device_uuid", value: string, ms: number) => {
        const { count } = await supabase
          .from("send_events")
          .select("id", { count: "exact", head: true })
          .eq(column, value)
          .gte("created_at", new Date(Date.now() - ms).toISOString());
        return count ?? 0;
      };
      for (const [column, value, hCap, dCap] of [
        ["user_id", user.id, hourlyCap, dailyCap],
        ["device_uuid", deviceUUID, deviceHourlyCap, deviceDailyCap],
      ] as const) {
        if (hCap >= 0 && await countSince(column, value, 60 * 60 * 1000) >= hCap) {
          return json({ error: "rate_limited", window: "hour" }, 429);
        }
        if (dCap >= 0 && await countSince(column, value, 24 * 60 * 60 * 1000) >= dCap) {
          return json({ error: "rate_limited", window: "day" }, 429);
        }
      }
      await supabase.from("send_events").insert({ user_id: user.id, device_uuid: deviceUUID, card_id: cardID });
    }

    // ----------------------------------------------------------------
    // Content-safety gate: everything this function can see is checked
    // server-side, so a modified app can't skip the app's own checks. That is
    // the nicknames, message preview, ink messages, other typed text, and
    // every image file the app staged for this card (card-staging, private).
    // Files that pass are copied to the public card-images bucket by
    // _shared/cardImages.ts, so nothing public is ever written by the app and
    // an image can't be swapped after it was checked. Fails closed. A rejected
    // card's staged files are removed.
    // ----------------------------------------------------------------
    {
      const cardPath = cardID.toLowerCase();
      const result = await moderateAndPromote(supabase, user.id, cardPath, {
        // The fields saved on the card, plus the app's list of every other
        // typed text (full message, captions, greetings banner, border text).
        // Capped so a request can't make the check unreasonably large.
        texts: [
          senderNickname, recipientNickname, messagePreview, frontInkMessage, backInkMessage,
          ...(Array.isArray(extraTexts) ? extraTexts.slice(0, 50) : []),
        ]
          .filter((t): t is string => typeof t === "string")
          .map((t) => t.slice(0, 2000)),
        requireWeb: true,
      });
      if (result.status === "error") return json({ error: "moderation_unavailable" }, 503);
      if (result.status === "missing") return json({ error: "images_missing", names: result.names }, 400);
      if (result.status === "flagged") {
        const verdict = result.verdict;
        await removeFolder(supabase, "card-images", user.id, cardPath);
        // Record the block and apply the strike rules (blocked photos and
        // harassment count; see _shared/contentBlocks.ts).
        const outcome = await recordContentBlock(supabase, {
          userId: user.id,
          deviceUUID,
          photo: verdict.photo,
          text: verdict.text,
          categories: verdict.categories,
          fingerprints: verdict.fingerprints,
          scores: verdict.scores,
        });
        if (outcome.suspended) return json({ error: "suspended" }, 403);
        return json({ error: "content_flagged", categories: verdict.categories, warning: outcome.warning }, 422);
      }
    }

    // ----------------------------------------------------------------
    // Build storage URLs
    // ----------------------------------------------------------------
    const supabaseURL    = Deno.env.get("SUPABASE_URL")!;
    const cardWebUrl     = `https://carddropapp.com/card/${cardID}`;
    // CardUploadService.swift uploads to a LOWERCASED path
    // (cardID.uuidString.lowercased()), but cardID here is Swift's
    // UUID.uuidString, which is uppercase — must lowercase it here too or
    // these URLs 404/400 against the real object path.
    const cardIDPath     = cardID.toLowerCase();
    const teaserImageUrl = `${supabaseURL}/storage/v1/object/public/card-images/${user.id}/${cardIDPath}.jpg`;
    const thumbnailUrl   = `${supabaseURL}/storage/v1/object/public/card-images/${user.id}/${cardIDPath}_thumb.jpg`;

    // Every card link expires card_link_days (zz_config, default 90) after it is
    // sent; each real web view pushes it out further (extend-card-link).
    const { data: linkDaysRow } = await supabase
      .from("zz_config")
      .select("value")
      .eq("key", "card_link_days")
      .maybeSingle();
    const linkDays = parseInt(linkDaysRow?.value ?? "", 10);
    const expiresAt = new Date(Date.now() + (linkDays > 0 ? linkDays : 90) * 24 * 60 * 60 * 1000).toISOString();

    // ----------------------------------------------------------------
    // Ensure user row exists (auth user may exist before users row is created)
    // ----------------------------------------------------------------
    await supabase.from("users").upsert({ id: user.id }, { onConflict: "id", ignoreDuplicates: true });

    // ----------------------------------------------------------------
    // Upsert card record
    // ----------------------------------------------------------------
    const { error: insertError } = await supabase
      .from("cards")
      .upsert({
        id:                 cardID,
        sender_id:          user.id,
        sender_nickname:    senderNickname    ?? null,
        recipient_nickname: recipientNickname ?? null,
        message_preview:    messagePreview   ?? null,
        teaser_image_url:   teaserImageUrl,
        thumbnail_url:      thumbnailUrl,
        device_uuid:        deviceUUID,
        is_portrait:        isPortrait       ?? true,
        front_ink_message:  frontInkMessage  ?? null,
        back_ink_message:   backInkMessage   ?? null,
        design_features:    designFeatures   ?? null,
        expires_at:         expiresAt,
        sent_at:            new Date().toISOString(),
      });

    if (insertError) {
      console.error("Insert error:", insertError.code, insertError.message);
      return json({ error: "Failed to insert card", detail: insertError.message }, 500);
    }

    // ----------------------------------------------------------------
    // Insert recipient row (if any recipient data provided)
    // ----------------------------------------------------------------
    const firstName = recipientFirstName ?? (recipientName ?? null);
    const lastName  = recipientLastName  ?? null;
    const hasRecipient = firstName || lastName || recipientEmail || recipientPhone;
    if (hasRecipient) {
      await supabase.from("card_recipients").insert({
        card_id:    cardID,
        first_name: firstName,
        last_name:  lastName,
        email:      recipientEmail ?? null,
        phone:      recipientPhone ?? null,
        nickname:   recipientNickname ?? null,
      });
    }

    // ----------------------------------------------------------------
    // Increment send counters
    // ----------------------------------------------------------------
    await supabase
      .from("users")
      .update({
        sends_this_month: sendsMonth    + 1,
        sends_lifetime:   sendsLifetime + 1,
      })
      .eq("id", user.id);

    // Per-device counters (links the device to this account as a side effect).
    await supabase.from("user_devices").upsert(
      {
        device_uuid:      deviceUUID,
        user_id:          user.id,
        sends_this_month: deviceMonth + 1,
        sends_lifetime:   deviceLifetime + 1,
        month_key:        monthKey,
      },
      { onConflict: "device_uuid" },
    );

    // ----------------------------------------------------------------
    // Return result with remaining counts (-1 = unlimited). For capped tiers
    // the stricter of the account and device counts applies.
    // ----------------------------------------------------------------
    const usedMonth    = deviceCapped ? Math.max(sendsMonth, deviceMonth) : sendsMonth;
    const usedLifetime = deviceCapped ? Math.max(sendsLifetime, deviceLifetime) : sendsLifetime;
    const remainingMonthly  = monthlyLimit  === -1 ? -1 : monthlyLimit  - usedMonth    - 1;
    const remainingLifetime = lifetimeLimit === -1 ? -1 : lifetimeLimit - usedLifetime - 1;

    return json({
      cardURL:                cardWebUrl,
      sendsRemainingMonthly:  remainingMonthly,
      sendsRemainingLifetime: remainingLifetime,
      tier,
    });

  } catch (err) {
    console.error("send-card error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// A user counts as verified if the verify-email-otp function marked them
// (app_metadata is writable only with the service role) or they signed in
// with Apple (Supabase adds an apple identity only after validating Apple's
// token). user_metadata.send_unlocked is NOT trusted: users can write it.
// The flag also needs Supabase's own email_confirmed_at (set only by the auth
// server when a code is really verified), so a flag set by mistake or by a bad
// manual edit does not grant verified privileges.
function isVerifiedUser(user: {
  app_metadata?: Record<string, unknown> | null;
  identities?: { provider: string }[] | null;
  email_confirmed_at?: string | null;
}): boolean {
  return (user.app_metadata?.send_unlocked === true && !!user.email_confirmed_at) ||
    (user.identities ?? []).some((i) => i.provider === "apple");
}
