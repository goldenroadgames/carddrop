import { createClient } from "jsr:@supabase/supabase-js@2";

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
            isPortrait, frontInkMessage, backInkMessage, designFeatures } = await req.json();

    if (!cardID)    return json({ error: "cardID required" }, 400);
    if (!deviceUUID) return json({ error: "deviceUUID required" }, 400);

    // ----------------------------------------------------------------
    // Ban check — device-level, bypasses RLS via service role
    // ----------------------------------------------------------------
    const { data: deviceRow } = await supabase
      .from("user_devices")
      .select("banned")
      .eq("device_uuid", deviceUUID)
      .maybeSingle();

    if (deviceRow?.banned) {
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
    const isVerified  = isVerifiedUser(user);

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

    // ----------------------------------------------------------------
    // Return result with remaining counts (-1 = unlimited)
    // ----------------------------------------------------------------
    const remainingMonthly  = monthlyLimit  === -1 ? -1 : monthlyLimit  - sendsMonth  - 1;
    const remainingLifetime = lifetimeLimit === -1 ? -1 : lifetimeLimit - sendsLifetime - 1;

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
function isVerifiedUser(user: {
  app_metadata?: Record<string, unknown> | null;
  identities?: { provider: string }[] | null;
}): boolean {
  return user.app_metadata?.send_unlocked === true ||
    (user.identities ?? []).some((i) => i.provider === "apple");
}
