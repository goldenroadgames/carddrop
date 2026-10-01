import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  try {
    const { email } = await req.json();
    if (!email) return json({ error: "email required" }, 400);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Generate the verification link
    const { data, error: linkError } = await supabase.auth.admin.generateLink({
      type: "magiclink",
      email,
      options: { redirectTo: "carddrop://" },
    });

    if (linkError || !data?.properties?.action_link) {
      console.error("generateLink error:", linkError);
      return json({ error: linkError?.message ?? "Failed to generate link" }, 400);
    }

    const link = data.properties.action_link;

    // Send via Resend API directly — bypasses Supabase SMTP routing
    const resendRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${Deno.env.get("RESEND_API_KEY")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: Deno.env.get("RESEND_FROM_EMAIL"),
        to: email,
        subject: "Verify your CardDrop email",
        html: `
          <p>Hi,</p>
          <p>Tap the button below to verify your email and unlock sending cards.</p>
          <p><a href="${link}" style="background:#2563eb;color:white;padding:12px 24px;border-radius:8px;text-decoration:none;display:inline-block;">Verify Email</a></p>
          <p>Or copy this link: ${link}</p>
        `,
      }),
    });

    if (!resendRes.ok) {
      const body = await resendRes.text();
      console.error("Resend error:", body);
      return json({ error: "Failed to send email" }, 500);
    }

    return json({ ok: true });
  } catch (err) {
    console.error("resend-confirmation error:", err);
    return json({ error: "Internal server error" }, 500);
  }
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
