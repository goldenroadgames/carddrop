import { createClient } from "jsr:@supabase/supabase-js@2";

// Verifies the 6-digit email code and, only if it is valid, marks the user
// verified by writing app_metadata.send_unlocked = true — app_metadata can
// only be written with the service role, unlike user_metadata, which any
// signed-in user can write to themselves. The flag is set on the user the
// verification itself returned, so it is bound to the email whose code was
// actually entered (including a corrected email that creates a new account).
//
// Returns that user's session tokens; the app calls auth.setSession with them
// (verifying here replaces the app's own auth.verifyOTP call, which is what
// used to sign the user in).
Deno.serve(async (req) => {
  try {
    const { email, code } = await req.json();
    if (!email || !code) return json({ error: "email and code required" }, 400);

    const url = Deno.env.get("SUPABASE_URL")!;

    // Anon-key client: verifyOtp needs no privileges, and must not run as
    // the service role.
    const anon = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data, error } = await anon.auth.verifyOtp({
      email,
      token: String(code).trim(),
      type: "email",
    });
    if (error || !data?.session || !data?.user) {
      return json({ error: "invalid_code" }, 401);
    }

    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { error: updateError } = await admin.auth.admin.updateUserById(
      data.user.id,
      { app_metadata: { ...(data.user.app_metadata ?? {}), send_unlocked: true } },
    );
    if (updateError) {
      console.error("updateUserById error:", updateError);
      return json({ error: "update_failed" }, 500);
    }

    return json({
      access_token: data.session.access_token,
      refresh_token: data.session.refresh_token,
    });
  } catch (err) {
    console.error("verify-email-otp error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
