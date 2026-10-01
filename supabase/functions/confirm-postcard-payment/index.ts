import { createClient } from "jsr:@supabase/supabase-js@2";

// Called right after StripePaymentSheet reports .completed. Never trusts
// that claim alone — re-checks the PaymentIntent's actual status directly
// with Stripe before flipping physical_orders to 'authorized', since only
// Stripe knows whether the authorization hold really succeeded. This does
// NOT charge the customer — see migration 030 and submit-to-lob, which
// captures the hold on LOB success or cancels it on LOB failure.
//
// Idempotent: if the order is already past pending_payment (e.g. this gets
// called twice), short-circuits before touching anything again, which is
// also what keeps the promo_code_redemptions insert below from ever
// double-firing — it only runs on the single pending_payment -> authorized
// transition.
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

    const { orderID } = await req.json();
    if (!orderID) return json({ error: "orderID required" }, 400);

    // ----------------------------------------------------------------
    // Fetch the order — must belong to the caller. Re-fetched ourselves,
    // never trust a client-supplied status.
    // ----------------------------------------------------------------
    const { data: order, error: orderError } = await supabase
      .from("physical_orders")
      .select("id, sender_id, status, stripe_payment_intent_id, promo_code_id, discount_cents")
      .eq("id", orderID)
      .maybeSingle();

    if (orderError || !order) return json({ error: "order_not_found" }, 404);
    if (order.sender_id !== user.id) return json({ error: "unauthorized" }, 403);

    if (order.status === "authorized" || order.status === "paid" || order.status === "submitted_to_lob") {
      return json({ paid: true, status: order.status });
    }
    if (order.status !== "pending_payment") {
      return json({ paid: false, status: order.status });
    }
    if (!order.stripe_payment_intent_id) {
      return json({ error: "no_payment_intent" }, 400);
    }

    // ----------------------------------------------------------------
    // Ask Stripe directly whether the authorization actually succeeded.
    // Manual capture (see create-postcard-payment-intent) means "succeeded"
    // never happens here — a successful PaymentSheet completion lands the
    // intent at "requires_capture" (funds held, not charged yet). The
    // actual charge only happens in submit-to-lob, once LOB accepts.
    // ----------------------------------------------------------------
    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY")!;
    const stripeResponse = await fetch(
      `https://api.stripe.com/v1/payment_intents/${order.stripe_payment_intent_id}`,
      { headers: { "Authorization": "Basic " + btoa(`${stripeKey}:`) } }
    );
    const intent = await stripeResponse.json();

    if (!stripeResponse.ok) {
      console.error("Stripe payment intent lookup error:", intent);
      return json({ error: "stripe_error", detail: intent?.error?.message ?? "lookup failed" }, 502);
    }

    if (intent.status !== "requires_capture") {
      return json({ paid: false, status: intent.status });
    }

    // ----------------------------------------------------------------
    // Flip the order to authorized (held, not yet charged).
    // ----------------------------------------------------------------
    const { error: updateError } = await supabase
      .from("physical_orders")
      .update({ status: "authorized", updated_at: new Date().toISOString() })
      .eq("id", order.id);

    if (updateError) {
      console.error("Failed to mark order authorized:", updateError);
      return json({ error: "save_failed", detail: updateError.message }, 500);
    }

    // ----------------------------------------------------------------
    // Record the promo redemption now that the order has an authorized
    // hold — not at validation/intent-creation time (see migration 025).
    // Still recorded here (before the actual capture) since the discount
    // itself was already baked into the authorized amount.
    // ----------------------------------------------------------------
    if (order.promo_code_id) {
      const { error: redemptionError } = await supabase
        .from("promo_code_redemptions")
        .insert({
          promo_code_id: order.promo_code_id,
          user_id: user.id,
          order_id: order.id,
          discount_cents: order.discount_cents ?? 0,
        });
      if (redemptionError) {
        console.error("Failed to record promo redemption:", redemptionError);
      }
    }

    return json({ paid: true, status: "authorized" });

  } catch (err) {
    console.error("confirm-postcard-payment error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
