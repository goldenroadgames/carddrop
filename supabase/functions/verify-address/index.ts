import { createClient } from "jsr:@supabase/supabase-js@2";

// Verifies a saved mailing address (user_address_book row) against LOB's
// US address-verification API, and caches the result on the row so the
// same address is never re-verified (and re-paid-for) twice. Only ever
// takes an addressID — never raw address text from the client — and
// re-fetches the row itself (service role) so the verified result can
// never drift from what's actually stored.
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

    const { addressID } = await req.json();
    if (!addressID) return json({ error: "addressID required" }, 400);

    // ----------------------------------------------------------------
    // Fetch the address row — must belong to the caller.
    // ----------------------------------------------------------------
    const { data: address, error: fetchError } = await supabase
      .from("user_address_book")
      .select("id, user_id, street, city, state, zip, country")
      .eq("id", addressID)
      .maybeSingle();

    if (fetchError || !address) return json({ error: "address_not_found" }, 404);
    if (address.user_id !== user.id) return json({ error: "unauthorized" }, 403);
    if (!address.street || !address.city || !address.state || !address.zip) {
      return json({ error: "incomplete_address" }, 400);
    }

    // ----------------------------------------------------------------
    // Call LOB's US address-verification API.
    // Auth: HTTP Basic, API key as username, blank password.
    // ----------------------------------------------------------------
    const lobKey = Deno.env.get("LOB_API_KEY")!;
    const lobResponse = await fetch("https://api.lob.com/v1/us_verifications", {
      method: "POST",
      headers: {
        "Authorization": "Basic " + btoa(`${lobKey}:`),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        primary_line: address.street,
        city: address.city,
        state: address.state,
        zip_code: address.zip,
      }),
    });

    const lobResult = await lobResponse.json();

    if (!lobResponse.ok) {
      console.error("LOB verification error:", lobResult);
      return json({ error: "lob_error", detail: lobResult?.error?.message ?? "verification failed" }, 502);
    }

    // "deliverable" and "deliverable_unnecessary_unit" are treated as
    // verified; anything else (deliverable_incorrect_unit,
    // deliverable_missing_unit, undeliverable) is not — the caller should
    // show the suggested correction and let the user fix it.
    const deliverability: string = lobResult.deliverability ?? "undeliverable";
    const verified = deliverability === "deliverable" || deliverability === "deliverable_unnecessary_unit";

    if (!verified) {
      return json({
        verified: false,
        deliverability,
        message: "This address couldn't be verified as deliverable. Please double-check it.",
      });
    }

    // ----------------------------------------------------------------
    // Cache the verified result, standardizing the stored address to
    // match what LOB will actually print/mail.
    // ----------------------------------------------------------------
    const components = lobResult.components ?? {};
    const update = {
      street: [lobResult.primary_line, lobResult.secondary_line].filter(Boolean).join(" "),
      city: components.city ?? address.city,
      state: components.state ?? address.state,
      zip: components.zip_code ?? address.zip,
      country: "US",
      is_verified: true,
      verified_at: new Date().toISOString(),
      lob_verification_id: lobResult.id ?? null,
      updated_at: new Date().toISOString(),
    };

    const { data: updatedRow, error: updateError } = await supabase
      .from("user_address_book")
      .update(update)
      .eq("id", addressID)
      .select()
      .single();

    if (updateError) {
      console.error("Failed to save verification result:", updateError);
      return json({ error: "save_failed", detail: updateError.message }, 500);
    }

    return json({ verified: true, deliverability, address: updatedRow });

  } catch (err) {
    console.error("verify-address error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
