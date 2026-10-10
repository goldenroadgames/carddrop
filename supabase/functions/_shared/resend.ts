// Minimal Resend sender. Uses the existing RESEND_API_KEY and RESEND_FROM_EMAIL
// secrets (RESEND_REPLY_TO optional). Never throws: a failed email must not fail the
// caller. Returns true if Resend accepted the message.
export async function sendEmail(to: string, subject: string, text: string): Promise<boolean> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    console.error("sendEmail: RESEND_API_KEY not set, skipping email to", to);
    return false;
  }
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: Deno.env.get("RESEND_FROM_EMAIL") ?? "CardDrop <noreply@carddropapp.com>",
        to: [to],
        reply_to: Deno.env.get("RESEND_REPLY_TO") ?? undefined,
        subject,
        text,
      }),
    });
    if (!res.ok) {
      console.error("sendEmail failed:", res.status, await res.text());
      return false;
    }
    return true;
  } catch (err) {
    console.error("sendEmail error:", err);
    return false;
  }
}
