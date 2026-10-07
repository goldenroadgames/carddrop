import { createClient } from "jsr:@supabase/supabase-js@2";

// Creates a physical_orders row (status: pending_payment) for a card being
// mailed via LOB, then creates a matching Stripe PaymentIntent for the
// server-computed amount. The client only ever supplies which addresses and
// size it wants and, optionally, a promo code — never an amount. Price comes
// from zz_postcard_current_pricing (see migration 024) and any promo discount
// is re-validated here, server-side, exactly like validate-promo-code, so a
// client can't fabricate a discount by calling this directly.
//
// Calls Stripe's REST API directly via fetch (HTTP Basic auth, secret key as
// username) rather than an SDK, matching how verify-address already calls
// LOB — no new dependency, same style throughout supabase/functions.
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

    // Physical mail involves real payment and a real mailing address, so
    // this is enforced here too, not just in the app's UI — the client-side
    // gate (PreviewSendStepView) only stops someone using the app normally;
    // it does nothing against a direct API call with a valid but unverified
    // account's token.
    if (!isVerifiedUser(user)) {
      return json({ error: "email_not_verified" }, 403);
    }

    const { cardID, senderAddressID, recipientAddressID, size, promoCode } = await req.json();
    if (!cardID) return json({ error: "cardID required" }, 400);
    if (!senderAddressID) return json({ error: "senderAddressID required" }, 400);
    if (!recipientAddressID) return json({ error: "recipientAddressID required" }, 400);
    if (size !== "4x6" && size !== "6x9") return json({ error: "invalid size" }, 400);

    // ----------------------------------------------------------------
    // Re-fetch both addresses ourselves — never trust client-supplied
    // address text for what gets printed/mailed or billed. Must belong
    // to the caller.
    // ----------------------------------------------------------------
    const { data: sender, error: senderError } = await supabase
      .from("user_address_book")
      .select("id, user_id, first_name, last_name, street, city, state, zip, country")
      .eq("id", senderAddressID)
      .maybeSingle();
    if (senderError || !sender) return json({ error: "sender_address_not_found" }, 404);
    if (sender.user_id !== user.id) return json({ error: "unauthorized" }, 403);

    const { data: recipient, error: recipientError } = await supabase
      .from("user_address_book")
      .select("id, user_id, first_name, last_name, street, city, state, zip, country")
      .eq("id", recipientAddressID)
      .maybeSingle();
    if (recipientError || !recipient) return json({ error: "recipient_address_not_found" }, 404);
    if (recipient.user_id !== user.id) return json({ error: "unauthorized" }, 403);

    // ----------------------------------------------------------------
    // Current price for the size.
    // ----------------------------------------------------------------
    const { data: pricing, error: pricingError } = await supabase
      .from("zz_postcard_current_pricing")
      .select("amount_cents, currency")
      .eq("size", size)
      .maybeSingle();
    if (pricingError || !pricing) {
      console.error("pricing lookup error:", pricingError);
      return json({ error: "pricing_unavailable" }, 500);
    }

    // ----------------------------------------------------------------
    // Optional promo code — same validation rules as validate-promo-code,
    // duplicated here (not called over HTTP) since this function must
    // trust nothing but its own re-check before charging the card.
    // ----------------------------------------------------------------
    let promoCodeID: string | null = null;
    let discountCents = 0;
    let isFreeOrder = false;

    if (promoCode) {
      const { data: promo, error: promoError } = await supabase
        .from("zz_promo_codes")
        .select("id, discount_type, discount_value, applicable_sizes, max_redemptions, per_user_limit, starts_at, expires_at, is_active, is_free, restricted, allowed_email_domains")
        .ilike("code", String(promoCode).trim())
        .maybeSingle();

      if (promoError) {
        console.error("promo lookup error:", promoError);
        return json({ error: "promo_lookup_failed" }, 500);
      }

      const now = new Date();
      const promoValid = !!promo &&
        promo.is_active &&
        (!promo.starts_at || new Date(promo.starts_at) <= now) &&
        (!promo.expires_at || new Date(promo.expires_at) > now) &&
        (!promo.applicable_sizes || promo.applicable_sizes.includes(size));

      if (!promoValid) return json({ error: "invalid_promo_code" }, 400);

      // Restricted codes: only allow-listed accounts. Same error as an
      // invalid code so a restricted code's existence can't be probed.
      if (promo.restricted && !(await isAllowedForRestrictedPromo(supabase, promo, user))) {
        return json({ error: "invalid_promo_code" }, 400);
      }

      if (promo.max_redemptions != null) {
        const { count } = await supabase
          .from("promo_code_redemptions")
          .select("id", { count: "exact", head: true })
          .eq("promo_code_id", promo.id);
        if ((count ?? 0) >= promo.max_redemptions) {
          return json({ error: "promo_redemption_limit_reached" }, 400);
        }
      }
      if (promo.per_user_limit != null) {
        const { count } = await supabase
          .from("promo_code_redemptions")
          .select("id", { count: "exact", head: true })
          .eq("promo_code_id", promo.id)
          .eq("user_id", user.id);
        if ((count ?? 0) >= promo.per_user_limit) {
          return json({ error: "promo_already_used" }, 400);
        }
      }

      promoCodeID = promo.id;
      if (promo.is_free) {
        // Free code: the whole price comes off, no 50-cent Stripe floor,
        // and Stripe is skipped entirely below (see migration 043).
        isFreeOrder = true;
        discountCents = pricing.amount_cents;
      } else {
        discountCents = computeDiscountCents(promo.discount_type, promo.discount_value, pricing.amount_cents);
      }
    }

    const finalAmountCents = pricing.amount_cents - discountCents;

    // ----------------------------------------------------------------
    // Create the order row first (pending_payment, no Stripe id yet) so
    // the PaymentIntent's metadata can reference a real order id.
    // ----------------------------------------------------------------
    // ----------------------------------------------------------------
    // physical_orders.card_id has a foreign key to cards(id) — a card
    // going straight to physical mail (never digitally sent first) has no
    // cards row yet, so ensure one exists before inserting the order.
    // ignoreDuplicates means this is a no-op if the card was already sent
    // digitally at some point — never overwrites real send data.
    //
    // Note: card_html_url is NOT NULL in the committed migration
    // (001_schema.sql) but the live database no longer has that column at
    // all (confirmed via a PostgREST "could not find column" error) — the
    // schema has drifted from the migration files. Only setting columns
    // confirmed to exist live.
    // ----------------------------------------------------------------
    const { error: cardUpsertError } = await supabase
      .from("cards")
      .upsert(
        { id: cardID, sender_id: user.id, teaser_image_url: "" },
        { onConflict: "id", ignoreDuplicates: true }
      );
    if (cardUpsertError) {
      console.error("card upsert error:", cardUpsertError);
      return json({ error: "card_setup_failed", detail: cardUpsertError.message }, 500);
    }

    const { data: order, error: insertError } = await supabase
      .from("physical_orders")
      .insert({
        card_id: cardID,
        sender_id: user.id,
        recipient_first_name: recipient.first_name,
        recipient_last_name: recipient.last_name,
        recipient_street: recipient.street,
        recipient_city: recipient.city,
        recipient_state: recipient.state,
        recipient_zip: recipient.zip,
        recipient_country: recipient.country,
        sender_first_name: sender.first_name,
        sender_last_name: sender.last_name,
        sender_street: sender.street,
        sender_city: sender.city,
        sender_state: sender.state,
        sender_zip: sender.zip,
        sender_country: sender.country,
        recipient_address_book_id: recipient.id,
        sender_address_book_id: sender.id,
        card_size: size,
        amount_cents: finalAmountCents,
        currency: pricing.currency,
        // A free order has nothing to pay, so it starts already 'authorized'
        // (what confirm-postcard-payment would otherwise flip it to).
        status: isFreeOrder ? "authorized" : "pending_payment",
        promo_code_id: promoCodeID,
        discount_cents: discountCents,
      })
      .select("id")
      .single();

    if (insertError || !order) {
      console.error("order insert error:", insertError);
      return json({ error: "order_creation_failed", detail: insertError?.message }, 500);
    }

    // ----------------------------------------------------------------
    // Free order: no Stripe. Record the redemption now (confirm-postcard-
    // payment never runs for it) so max_redemptions / per_user_limit count
    // it immediately. submit-to-lob releases the slot if LOB rejects the
    // card, so a failed attempt doesn't burn a limited code.
    // ----------------------------------------------------------------
    if (isFreeOrder) {
      const { error: redemptionError } = await supabase
        .from("promo_code_redemptions")
        .insert({
          promo_code_id: promoCodeID,
          user_id: user.id,
          order_id: order.id,
          discount_cents: discountCents,
        });
      if (redemptionError) {
        console.error("Failed to record free-order promo redemption:", redemptionError);
        await supabase
          .from("physical_orders")
          .update({ status: "failed", error_message: "Could not record promo redemption" })
          .eq("id", order.id);
        return json({ error: "save_failed", detail: redemptionError.message }, 500);
      }
      return json({
        orderID: order.id,
        paymentRequired: false,
        clientSecret: null,
        amountCents: 0,
        discountCents,
        currency: pricing.currency,
      });
    }

    // ----------------------------------------------------------------
    // Create the Stripe PaymentIntent for the server-computed amount.
    // Stripe's API takes form-encoded params, not JSON.
    // ----------------------------------------------------------------
    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY")!;
    const params = new URLSearchParams();
    params.set("amount", String(finalAmountCents));
    params.set("currency", pricing.currency);
    // Card only — no ACH/bank debit. A $3-10 postcard doesn't need a
    // multi-day settlement rail, and card payments confirm synchronously,
    // which is what lets a client-side payment-confirmation step be correct.
    params.set("payment_method_types[]", "card");
    // Manual capture: PaymentSheet completion only places an authorization
    // hold, no charge yet. submit-to-lob captures it on LOB success or
    // cancels it on LOB failure — see migration 030 — so a card that LOB
    // rejects (bad address, content violation) never actually gets charged.
    params.set("capture_method", "manual");
    params.set("metadata[order_id]", order.id);
    params.set("metadata[card_id]", cardID);
    params.set("metadata[user_id]", user.id);
    params.set("metadata[app]", "carddrop");
    params.set("metadata[product_type]", "single_postcard");

    const stripeResponse = await fetch("https://api.stripe.com/v1/payment_intents", {
      method: "POST",
      headers: {
        "Authorization": "Basic " + btoa(`${stripeKey}:`),
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: params.toString(),
    });

    const intent = await stripeResponse.json();

    if (!stripeResponse.ok) {
      console.error("Stripe payment intent error:", intent);
      await supabase
        .from("physical_orders")
        .update({ status: "failed", error_message: intent?.error?.message ?? "Stripe error" })
        .eq("id", order.id);
      return json({ error: "stripe_error", detail: intent?.error?.message ?? "payment intent failed" }, 502);
    }

    // ----------------------------------------------------------------
    // Record the PaymentIntent id on the order now that it exists.
    // ----------------------------------------------------------------
    const { error: updateError } = await supabase
      .from("physical_orders")
      .update({ stripe_payment_intent_id: intent.id })
      .eq("id", order.id);

    if (updateError) {
      console.error("Failed to save payment intent id:", updateError);
      return json({ error: "save_failed", detail: updateError.message }, 500);
    }

    return json({
      orderID: order.id,
      paymentRequired: true,
      clientSecret: intent.client_secret,
      amountCents: finalAmountCents,
      discountCents,
      currency: pricing.currency,
    });

  } catch (err) {
    console.error("create-postcard-payment-intent error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

// Stripe requires a minimum charge (50 cents USD) — a discount is clamped
// so the final amount never drops below that floor rather than to zero.
// For price_override, discountValue IS the resulting price itself (not an
// amount off) — clamping to >= 0 here also guarantees an override can never
// make the customer pay MORE than the current price.
function computeDiscountCents(discountType: string, discountValue: number, amountCents: number): number {
  const MIN_CHARGE_CENTS = 50;
  let raw: number;
  if (discountType === "percent") {
    raw = Math.round(amountCents * discountValue / 100);
  } else if (discountType === "price_override") {
    raw = amountCents - discountValue;
  } else {
    raw = discountValue;
  }
  return Math.max(0, Math.min(raw, amountCents - MIN_CHARGE_CENTS));
}

// Restricted promo codes (see migrations 043/044/045): the caller must have a
// VERIFIED email (Supabase's email_confirmed_at — the app's send_unlocked flag
// lives in user_metadata, which the user can write to themselves, so it is NOT
// proof) AND be allowed: on the allow-list by user id, on it by email, or at
// an allowed email domain (the domain itself or a subdomain of it).
async function isAllowedForRestrictedPromo(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  promo: { id: string; allowed_email_domains?: string[] | null },
  user: { id: string; email?: string | null; email_confirmed_at?: string | null },
): Promise<boolean> {
  if (!user.email_confirmed_at) return false;

  const { data: byId } = await supabase
    .from("zz_promo_code_allowed_users")
    .select("id")
    .eq("promo_code_id", promo.id)
    .eq("user_id", user.id)
    .limit(1);
  if (byId && byId.length > 0) return true;

  if (!user.email) return false;
  const email = user.email.toLowerCase();

  const domain = email.slice(email.lastIndexOf("@") + 1);
  for (const raw of promo.allowed_email_domains ?? []) {
    const d = String(raw).toLowerCase();
    if (domain === d || domain.endsWith("." + d)) return true;
  }

  // Exact, case-insensitive email match (escape ilike wildcards).
  const escaped = email.replace(/[\\%_]/g, (c) => `\\${c}`);
  const { data: byEmail } = await supabase
    .from("zz_promo_code_allowed_users")
    .select("id")
    .eq("promo_code_id", promo.id)
    .ilike("email", escaped)
    .limit(1);
  return !!byEmail && byEmail.length > 0;
}

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
