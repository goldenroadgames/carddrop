import { createClient } from "jsr:@supabase/supabase-js@2";

// Tells the app whether the caller has a free-postcard allowance and how many
// are left this calendar month, so the payment sheet can show it before the
// user taps Place Order. Display only: create-postcard-payment-intent
// re-computes this itself and is the one that actually applies it.
// Allowance rules: see migration 048_account_postcard_allowances.sql.
Deno.serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "unauthorized" }, 401);

    const jwt = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(jwt);
    if (authError || !user) return json({ error: "unauthorized" }, 401);

    // Matched by the caller's VERIFIED email (migration 052), never by user
    // id: a confirmed email, or an Apple identity (Apple verified it).
    const emailIsVerified = !!user.email &&
      (!!user.email_confirmed_at || (user.identities ?? []).some((i: { provider: string }) => i.provider === "apple"));
    const { data: allowance, error: allowanceError } = !emailIsVerified
      ? { data: null, error: null }
      : await supabase
        .from("zz_account_allowances")
        .select("free_postcards_per_month, expires_on")
        .eq("email", user.email!.toLowerCase())
        .maybeSingle();
    if (allowanceError) {
      console.error("allowance lookup error:", allowanceError);
      return json({ error: "allowance_lookup_failed" }, 500);
    }
    // expires_on is the last valid day (inclusive, UTC date); null = never.
    const expired = !!allowance?.expires_on &&
      allowance.expires_on < new Date().toISOString().slice(0, 10);
    if (!allowance || expired) return json({ hasAllowance: false, limit: 0, used: 0, remaining: 0 });

    const now = new Date();
    const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString();

    const { count, error: countError } = await supabase
      .from("physical_orders")
      .select("id", { count: "exact", head: true })
      .eq("sender_id", user.id)
      .eq("funded_by_allowance", true)
      .not("status", "in", "(failed,refunded)")
      .gte("created_at", monthStart);
    if (countError) {
      console.error("allowance usage count error:", countError);
      return json({ error: "allowance_lookup_failed" }, 500);
    }

    const limit = allowance.free_postcards_per_month as number;
    const used = count ?? 0;
    return json({ hasAllowance: true, limit, used, remaining: Math.max(0, limit - used) });
  } catch (err) {
    console.error("get-postcard-allowance error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
