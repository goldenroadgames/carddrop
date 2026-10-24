import { createClient } from "jsr:@supabase/supabase-js@2";

// Called by the signed-in app (JWT required). Stores or removes this device's
// push token and saves the user's notifications switch (users.notify_replies).
// Body:
//   { action: "register", token, environment: "sandbox" | "production", notifyReplies?: boolean }
//   { action: "unregister", token }        (sign-out)
//   { action: "settings", notifyReplies }  (switch changed in Profile > Settings)
// See carddrop/push_notifications_plan.md.
const TOKEN_RE = /^[0-9a-fA-F]{32,200}$/;

Deno.serve(async (req) => {
  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "unauthorized" }, 401);
    const { data: { user }, error: authError } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
    if (authError || !user) return json({ error: "unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    const action = body.action;
    const token = typeof body.token === "string" ? body.token.toLowerCase() : "";

    if (action === "register") {
      if (!TOKEN_RE.test(token)) return json({ error: "invalid" }, 400);
      const environment = body.environment === "sandbox" ? "sandbox" : "production";
      // A device token belongs to one account at a time: signing in as someone
      // else on this device moves it.
      const { error } = await supabase.from("push_tokens").upsert(
        { user_id: user.id, device_token: token, environment, updated_at: new Date().toISOString() },
        { onConflict: "device_token" },
      );
      if (error) {
        console.error("push token upsert error:", error.message);
        return json({ error: "try_later" }, 500);
      }
      if (typeof body.notifyReplies === "boolean") await saveSwitch(supabase, user.id, body.notifyReplies);
      return json({ status: "ok" });
    }

    if (action === "unregister") {
      if (!TOKEN_RE.test(token)) return json({ error: "invalid" }, 400);
      await supabase.from("push_tokens").delete().eq("device_token", token).eq("user_id", user.id);
      return json({ status: "ok" });
    }

    if (action === "settings") {
      if (typeof body.notifyReplies !== "boolean") return json({ error: "invalid" }, 400);
      const ok = await saveSwitch(supabase, user.id, body.notifyReplies);
      return ok ? json({ status: "ok" }) : json({ error: "try_later" }, 500);
    }

    return json({ error: "invalid" }, 400);
  } catch (err) {
    console.error("register-push-token error:", err);
    return json({ error: "try_later" }, 500);
  }
});

// deno-lint-ignore no-explicit-any
async function saveSwitch(supabase: any, userId: string, value: boolean): Promise<boolean> {
  const { error } = await supabase.from("users").update({ notify_replies: value }).eq("id", userId);
  if (error) console.error("notify_replies update error:", error.message);
  return !error;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
