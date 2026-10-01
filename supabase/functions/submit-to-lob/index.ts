import { createClient } from "jsr:@supabase/supabase-js@2";

// Submits an authorized (not yet charged — see migration 030) physical_orders
// row to LOB's Postcards API. Can't render anything itself — the
// print-resolution front/back images are rendered on-device (SwiftUI
// ImageRenderer) and already uploaded to the public card-images bucket by
// the time this runs; this function only takes their URLs and hands them to
// LOB, plus the order's own address/size snapshot. On LOB acceptance, this
// also captures the Stripe authorization hold (the actual charge); on LOB
// rejection, it cancels the hold instead so the customer is never charged
// for a postcard that never gets mailed.
//
// Idempotent: if the order has already moved past 'authorized' (e.g. this
// gets called twice), returns the existing lob_id rather than submitting
// twice.
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

    const { orderID, frontImageURL, backImageURL } = await req.json();
    if (!orderID) return json({ error: "orderID required" }, 400);
    if (!frontImageURL) return json({ error: "frontImageURL required" }, 400);
    if (!backImageURL) return json({ error: "backImageURL required" }, 400);

    // ----------------------------------------------------------------
    // Fetch the order — must belong to the caller, and must already be
    // paid. Everything mailed to LOB (addresses, size) comes from this
    // row's own snapshot, never from the request body.
    // ----------------------------------------------------------------
    const { data: order, error: orderError } = await supabase
      .from("physical_orders")
      .select(`
        id, sender_id, status, card_size, stripe_payment_intent_id,
        recipient_first_name, recipient_last_name, recipient_street,
        recipient_city, recipient_state, recipient_zip, recipient_country,
        sender_first_name, sender_last_name, sender_street,
        sender_city, sender_state, sender_zip, sender_country,
        lob_id, lob_tracking_number, lob_expected_delivery_date
      `)
      .eq("id", orderID)
      .maybeSingle();

    if (orderError || !order) return json({ error: "order_not_found" }, 404);
    if (order.sender_id !== user.id) return json({ error: "unauthorized" }, 403);

    if (order.status === "submitted_to_lob" || order.status === "printed" ||
        order.status === "mailed" || order.status === "delivered") {
      return json({
        submitted: true,
        lobID: order.lob_id,
        trackingNumber: order.lob_tracking_number,
        expectedDeliveryDate: order.lob_expected_delivery_date,
      });
    }
    // 'authorized' (not 'paid') — see migration 030 / confirm-postcard-payment.
    // The card hasn't been charged yet; LOB success below captures it.
    if (order.status !== "authorized") {
      return json({ error: "order_not_paid", status: order.status }, 400);
    }

    // ----------------------------------------------------------------
    // Sanity-check the image URLs point at this order's own card in our
    // own public bucket — the client supplies them (rendering can only
    // happen on-device), so this is the one check we CAN make without
    // re-rendering anything ourselves.
    // ----------------------------------------------------------------
    const supabaseURL = Deno.env.get("SUPABASE_URL")!;
    const expectedPrefix = `${supabaseURL}/storage/v1/object/public/card-images/${user.id}/`;
    if (!frontImageURL.startsWith(expectedPrefix) || !backImageURL.startsWith(expectedPrefix)) {
      return json({ error: "invalid_image_url" }, 400);
    }

    // ----------------------------------------------------------------
    // Call LOB's Postcards API.
    // ----------------------------------------------------------------
    const lobKey = Deno.env.get("LOB_API_KEY")!;
    const lobResponse = await fetch("https://api.lob.com/v1/postcards", {
      method: "POST",
      headers: {
        "Authorization": "Basic " + btoa(`${lobKey}:`),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        description: `CardDrop postcard ${order.id}`,
        to: {
          name: [order.recipient_first_name, order.recipient_last_name].filter(Boolean).join(" "),
          address_line1: order.recipient_street,
          address_city: order.recipient_city,
          address_state: order.recipient_state,
          address_zip: order.recipient_zip,
          address_country: normalizeCountry(order.recipient_country),
        },
        from: {
          name: [order.sender_first_name, order.sender_last_name].filter(Boolean).join(" "),
          address_line1: order.sender_street,
          address_city: order.sender_city,
          address_state: order.sender_state,
          address_zip: order.sender_zip,
          address_country: normalizeCountry(order.sender_country),
        },
        front: frontImageURL,
        back: backImageURL,
        size: order.card_size,
        mail_type: "usps_first_class",
        // A personal card someone paid to send to one specific recipient —
        // not bulk/promotional mail, so "operational" rather than
        // "marketing" (required by LOB's API as of a recent USPS-driven
        // policy change).
        use_type: "operational",
        metadata: { order_id: order.id },
      }),
    });

    const lobResult = await lobResponse.json();

    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY")!;

    if (!lobResponse.ok) {
      console.error("LOB postcard creation error:", lobResult);
      // Release the authorization hold — LOB rejected the postcard, so the
      // customer should never actually be charged for it (see migration 030).
      let cancelError: string | null = null;
      if (order.stripe_payment_intent_id) {
        const cancelResponse = await fetch(
          `https://api.stripe.com/v1/payment_intents/${order.stripe_payment_intent_id}/cancel`,
          { method: "POST", headers: { "Authorization": "Basic " + btoa(`${stripeKey}:`) } }
        );
        if (!cancelResponse.ok) {
          const cancelResult = await cancelResponse.json();
          console.error("Stripe cancel error:", cancelResult);
          cancelError = cancelResult?.error?.message ?? "cancel failed";
        }
      }
      // A free (promo) order has no PaymentIntent and recorded its promo
      // redemption up front — release that slot so a failed attempt doesn't
      // burn a limited code (see create-postcard-payment-intent).
      if (!order.stripe_payment_intent_id) {
        await supabase.from("promo_code_redemptions").delete().eq("order_id", order.id);
      }
      const lobMessage = lobResult?.error?.message ?? "LOB submission failed";
      await supabase
        .from("physical_orders")
        .update({
          status: "failed",
          error_message: cancelError
            ? `${lobMessage} (hold release failed: ${cancelError} — needs manual refund)`
            : lobMessage,
        })
        .eq("id", order.id);
      return json({ error: "lob_error", detail: lobMessage }, 502);
    }

    // ----------------------------------------------------------------
    // LOB accepted the postcard — capture the authorization hold now that
    // we're actually committed to mailing it. If the capture itself fails
    // (very rare — the hold was just confirmed valid moments earlier at
    // confirm-postcard-payment), the postcard is already committed with
    // LOB and can't be un-submitted, so we log it for manual follow-up
    // rather than blocking the order from completing.
    // ----------------------------------------------------------------
    // Free (promo) orders have no PaymentIntent — nothing to capture.
    let captureError: string | null = null;
    if (order.stripe_payment_intent_id) {
      const captureResponse = await fetch(
        `https://api.stripe.com/v1/payment_intents/${order.stripe_payment_intent_id}/capture`,
        { method: "POST", headers: { "Authorization": "Basic " + btoa(`${stripeKey}:`) } }
      );
      if (!captureResponse.ok) {
        const captureResult = await captureResponse.json();
        console.error("Stripe capture error:", captureResult);
        captureError = captureResult?.error?.message ?? "capture failed";
      }
    }

    // ----------------------------------------------------------------
    // Record LOB's response and flip the order to submitted_to_lob.
    // ----------------------------------------------------------------
    const { error: updateError } = await supabase
      .from("physical_orders")
      .update({
        status: "submitted_to_lob",
        lob_id: lobResult.id ?? null,
        lob_tracking_number: lobResult.tracking_number ?? null,
        lob_expected_delivery_date: lobResult.expected_delivery_date ?? null,
        error_message: captureError ? `Charge capture failed: ${captureError} — needs manual billing follow-up` : null,
        updated_at: new Date().toISOString(),
      })
      .eq("id", order.id);

    if (updateError) {
      console.error("Failed to save LOB submission result:", updateError);
      return json({ error: "save_failed", detail: updateError.message }, 500);
    }

    return json({
      submitted: true,
      lobID: lobResult.id ?? null,
      trackingNumber: lobResult.tracking_number ?? null,
      expectedDeliveryDate: lobResult.expected_delivery_date ?? null,
    });

  } catch (err) {
    console.error("submit-to-lob error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

// LOB requires a real ISO-3166 alpha-2 code. Stored addresses aren't
// guaranteed to already be one — the manual entry field is free text, and
// until recently the Contacts autofill path stored a localized country
// *name* (e.g. "United States") rather than its code. Normalizes the common
// cases rather than trusting what's stored; defaults to "US" since that's
// the only country this app supports mailing to/from today.
function normalizeCountry(value: string | null): string {
  const trimmed = (value ?? "").trim();
  if (/^[A-Za-z]{2}$/.test(trimmed)) return trimmed.toUpperCase();
  const knownNames: Record<string, string> = {
    "united states": "US",
    "united states of america": "US",
    "usa": "US",
    "u.s.a.": "US",
    "u.s.": "US",
  };
  return knownNames[trimmed.toLowerCase()] ?? "US";
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
