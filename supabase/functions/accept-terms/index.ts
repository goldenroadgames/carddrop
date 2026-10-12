import { createClient } from "jsr:@supabase/supabase-js@2";
import { liveTermsVersion, requiredTermsVersion } from "../_shared/terms.ts";

// The signed-in user agrees to the Terms of Service and Privacy Policy.
// Records WHEN and WHICH version: the "Last updated" date of the live Terms
// text (never a value the app supplies), falling back to the required version
// if the date line can't be read. Written with the service role: the app can't
// write these columns itself.
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

    const version = (await liveTermsVersion(supabase)) ?? (await requiredTermsVersion(supabase));
    if (!version) return json({ error: "terms_version_unavailable" }, 500);

    const { error } = await supabase
      .from("users")
      .upsert(
        { id: user.id, terms_accepted_at: new Date().toISOString(), terms_version: version },
        { onConflict: "id" },
      );
    if (error) {
      console.error("accept-terms error:", error);
      return json({ error: "internal" }, 500);
    }
    return json({ status: "ok", version });
  } catch (err) {
    console.error("accept-terms error:", err);
    return json({ error: "internal" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
