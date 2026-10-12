import { createClient } from "jsr:@supabase/supabase-js@2";
import { isBanned } from "../_shared/bans.ts";
import { moderateContent } from "../_shared/moderation.ts";
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
      .select("deleted_at, reported_at")
      .eq("id", cardID)
      .maybeSingle();
    if (existingCard?.deleted_at) return json({ error: "card_deleted" }, 410);
    // A reported card is locked: no resending it.
    if (existingCard?.reported_at) return json({ error: "card_unavailable" }, 403);

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
      .select("tier, sends_this_month, sends_lifetime")
      .eq("id", user.id)
      .maybeSingle();

    const sendsMonth    = userRow?.sends_this_month ?? 0;
    const sendsLifetime = userRow?.sends_lifetime   ?? 0;
    const dbTier        = userRow?.tier             ?? "free";

    // ----------------------------------------------------------------
    // Determine effective tier
    // Priority: unlimited (paid) > verified (OTP done) > unverified > anonymous
    // ----------------------------------------------------------------
    const isAnonymous = user.is_anonymous ?? false;

    let tier: string;
    if (dbTier === "unlimited")  tier = "unlimited";
    else if (isVerified)         tier = "verified";
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
    // Content-safety gate: everything this function can see is checked
    // server-side, so a modified app can't skip the app's own checks. That is
    // the nicknames, message preview, ink messages, and the already-uploaded
    // front and back images (images over 4 MB are not checked; the web-size
    // copies are far smaller). Fails closed. A rejected card's uploaded
    // images are public, so they are removed.
    // ----------------------------------------------------------------
    {
      const cardPath = cardID.toLowerCase();
      const images: Uint8Array[] = [];
      for (const name of [`${cardPath}.jpg`, `${cardPath}_back.jpg`]) {
        const { data: blob } = await supabase.storage.from("card-images").download(`${user.id}/${name}`);
        if (blob && blob.size <= 4 * 1024 * 1024) images.push(new Uint8Array(await blob.arrayBuffer()));
      }
      const verdict = await moderateContent(supabase, {
        // The fields saved on the card, plus the app's list of every other
        // typed text (full message, captions, greetings banner, border text).
        // Capped so a request can't make the check unreasonably large.
        texts: [
          senderNickname, recipientNickname, messagePreview, frontInkMessage, backInkMessage,
          ...(Array.isArray(extraTexts) ? extraTexts.slice(0, 50) : []),
        ]
          .filter((t): t is string => typeof t === "string")
          .map((t) => t.slice(0, 2000)),
        images,
      });
      if (verdict.status === "error") return json({ error: "moderation_unavailable" }, 503);
      if (verdict.status === "flagged") {
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

    // Unlimited tier gets permanent links; all others expire after 30 days
    const expiresAt = tier === "unlimited"
      ? null
      : new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString();

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
      console.error("Insert error:", insertError);
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
