import { createClient } from "jsr:@supabase/supabase-js@2";

// Validates a promo code against zz_promo_codes rules and, if valid,
// returns the computed discount against the current price for the chosen
// size. Read-only — never inserts a promo_code_redemptions row itself; that
// only happens once an order actually reaches 'paid' status (see the
// create-postcard-payment-intent / payment-confirmation flow), so an
// abandoned checkout never consumes a limited code's redemption slot.
//
// zz_promo_codes has no client SELECT policy, so this must run with the
// service role key — a client can never query the table directly and
// enumerate valid codes.
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

    const { code, size } = await req.json();
    if (!code) return json({ error: "code required" }, 400);
    if (size !== "4x6" && size !== "6x9") return json({ error: "invalid size" }, 400);

    // ----------------------------------------------------------------
    // Look up the code (case-insensitive, matches the unique index on
    // upper(code)).
    // ----------------------------------------------------------------
    const { data: promo, error: promoError } = await supabase
      .from("zz_promo_codes")
      .select("id, code, discount_type, discount_value, applicable_sizes, excludes_special_pricing, max_redemptions, per_user_limit, starts_at, expires_at, is_active, is_free, restricted, allowed_email_domains")
      .ilike("code", code.trim())
      .maybeSingle();

    if (promoError) {
      console.error("promo lookup error:", promoError);
      return json({ error: "lookup_failed", detail: promoError.message }, 500);
    }
    if (!promo) return json({ valid: false, reason: "not_found" });

    // Restricted codes: only accounts on the allow-list may use them. A
    // caller who isn't gets the same "not_found" as a nonexistent code so
    // the code's existence can't be probed.
    if (promo.restricted && !(await isAllowedForRestrictedPromo(supabase, promo, user))) {
      return json({ valid: false, reason: "not_found" });
    }
    if (!promo.is_active) return json({ valid: false, reason: "inactive" });

    const now = new Date();
    if (promo.starts_at && new Date(promo.starts_at) > now) {
      return json({ valid: false, reason: "not_yet_active" });
    }
    if (promo.expires_at && new Date(promo.expires_at) <= now) {
      return json({ valid: false, reason: "expired" });
    }
    if (promo.applicable_sizes && !promo.applicable_sizes.includes(size)) {
      return json({ valid: false, reason: "not_applicable_to_size" });
    }

    // ----------------------------------------------------------------
    // Redemption limits — counted from promo_code_redemptions, not a DB
    // constraint (see migration 025).
    // ----------------------------------------------------------------
    if (promo.max_redemptions != null) {
      const { count } = await supabase
        .from("promo_code_redemptions")
        .select("id", { count: "exact", head: true })
        .eq("promo_code_id", promo.id);
      if ((count ?? 0) >= promo.max_redemptions) {
        return json({ valid: false, reason: "redemption_limit_reached" });
      }
    }
    if (promo.per_user_limit != null) {
      const { count } = await supabase
        .from("promo_code_redemptions")
        .select("id", { count: "exact", head: true })
        .eq("promo_code_id", promo.id)
        .eq("user_id", user.id);
      if ((count ?? 0) >= promo.per_user_limit) {
        return json({ valid: false, reason: "already_used" });
      }
    }

    // ----------------------------------------------------------------
    // Compute the discount against the current price for the size.
    // ----------------------------------------------------------------
    const { data: pricing, error: pricingError } = await supabase
      .from("zz_postcard_current_pricing")
      .select("amount_cents, currency, effective_to")
      .eq("size", size)
      .maybeSingle();

    if (pricingError || !pricing) {
      console.error("pricing lookup error:", pricingError);
      return json({ error: "pricing_unavailable" }, 500);
    }

    // A non-null effective_to means a narrower, temporary window beat out
    // the size's standing open-ended row — i.e. a "special" price is
    // currently in effect (see migration 028). Promos flagged
    // excludes_special_pricing don't stack with those.
    if (promo.excludes_special_pricing && pricing.effective_to !== null) {
      return json({ valid: false, reason: "not_applicable_to_special_price" });
    }

    // A free code takes the whole price (no 50-cent Stripe floor — the
    // order never touches Stripe); see migration 043.
    const discount = promo.is_free
      ? pricing.amount_cents
      : computeDiscountCents(promo.discount_type, promo.discount_value, pricing.amount_cents);

    return json({
      valid: true,
      promoCodeID: promo.id,
      discountType: promo.discount_type,
      discountValue: promo.discount_value,
      amountCents: pricing.amount_cents,
      discountCents: discount,
      finalAmountCents: pricing.amount_cents - discount,
      currency: pricing.currency,
    });

  } catch (err) {
    console.error("validate-promo-code error:", err);
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
