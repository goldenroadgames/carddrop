import { createClient } from "jsr:@supabase/supabase-js@2";
import { moderateContent } from "../_shared/moderation.ts";

// Content-safety check for the iOS app's create steps. The app used to call
// OpenAI directly with a key compiled into the binary; now it calls this
// function (signed in, anonymous sign-ins included) and the key stays on the
// server (OPENAI_API_KEY secret).
//
// Body: { texts?: string[], image?: string }  (image = base64 JPEG)
// Reply: { status: "clean" } | { status: "flagged", categories: string[] }
// If the check can't run: HTTP 503 { error: "try_later" }. The app treats that
// as "can't check right now" and blocks the step with a "try again" message;
// send-card also re-checks everything it receives before a card is stored, and
// blocks if it can't run.
const MAX_TEXTS = 50;
const MAX_TEXT_CHARS = 2000;
const MAX_IMAGE_BYTES = 2 * 1024 * 1024;

Deno.serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "unauthorized" }, 401);
    const jwt = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(jwt);
    if (authError || !user) return json({ error: "unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    const texts: string[] = Array.isArray(body.texts)
      ? body.texts.filter((t: unknown) => typeof t === "string").slice(0, MAX_TEXTS)
        .map((t: string) => t.slice(0, MAX_TEXT_CHARS))
      : [];

    const images: Uint8Array[] = [];
    if (typeof body.image === "string" && body.image.length > 0) {
      try {
        const bytes = Uint8Array.from(atob(body.image), (c) => c.charCodeAt(0));
        if (bytes.length > MAX_IMAGE_BYTES) return json({ error: "invalid" }, 400);
        images.push(bytes);
      } catch {
        return json({ error: "invalid" }, 400);
      }
    }

    const verdict = await moderateContent(supabase, { texts, images });
    if (verdict.status === "error") return json({ error: "try_later" }, 503);
    if (verdict.status === "flagged") return json({ status: "flagged", categories: verdict.categories });
    return json({ status: "clean" });
  } catch (err) {
    console.error("moderate-content error:", err);
    return json({ error: "try_later" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
