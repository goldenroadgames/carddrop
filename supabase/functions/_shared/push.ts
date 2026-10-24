import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

// Sends an Apple push notification (APNs) to a card sender's devices when
// someone opens, replies to or reacts to their card. Secrets (Apple Developer > Keys,
// with Apple Push Notifications service enabled):
//   APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY (contents of the .p8)
// Never throws and never blocks the caller: a failed push is only logged.
// A token APNs reports as dead is deleted. Respects users.notify_replies.
// See carddrop/push_notifications_plan.md.

const BUNDLE_ID = "com.goldenroadgames.carddrop";

export type PushKind = "reply" | "reaction" | "opened";

const COPY: Record<PushKind, (emoji?: string) => string> = {
  opened: () => "Your card was opened",
  reply: () => "New reply on your card",
  reaction: (emoji) => (emoji ? `Someone reacted ${emoji} to your card` : "Someone reacted to your card"),
};

export async function sendPush(
  supabase: SupabaseClient,
  senderId: string | null,
  cardId: string,
  kind: PushKind,
  emoji?: string,
): Promise<void> {
  try {
    if (!senderId) return;
    const keyId = Deno.env.get("APNS_KEY_ID");
    const teamId = Deno.env.get("APNS_TEAM_ID");
    const privateKey = Deno.env.get("APNS_PRIVATE_KEY");
    if (!keyId || !teamId || !privateKey) {
      console.error("sendPush: APNS_KEY_ID / APNS_TEAM_ID / APNS_PRIVATE_KEY not set, skipping");
      return;
    }

    const { data: user } = await supabase
      .from("users")
      .select("notify_replies")
      .eq("id", senderId)
      .maybeSingle();
    if (user && user.notify_replies === false) return;

    const { data: tokens } = await supabase
      .from("push_tokens")
      .select("device_token, environment")
      .eq("user_id", senderId);
    if (!tokens || tokens.length === 0) return;

    const jwt = await providerToken(teamId, keyId, privateKey);
    const body = JSON.stringify({
      aps: { alert: { title: "CardDrop", body: COPY[kind](emoji) }, sound: "default" },
      cardID: cardId,
    });

    await Promise.all(tokens.map(async (t: { device_token: string; environment: string }) => {
      const host = t.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
      try {
        const res = await fetch(`https://${host}/3/device/${t.device_token}`, {
          method: "POST",
          headers: {
            authorization: `bearer ${jwt}`,
            "apns-topic": BUNDLE_ID,
            "apns-push-type": "alert",
            "apns-priority": "10",
          },
          body,
        });
        if (res.ok) return;
        const text = await res.text();
        console.error("APNs push failed:", res.status, text);
        // Dead or wrong-environment token: forget it.
        if (res.status === 410 || (res.status === 400 && /BadDeviceToken|DeviceTokenNotForTopic/.test(text))) {
          await supabase.from("push_tokens").delete().eq("device_token", t.device_token);
        }
      } catch (err) {
        console.error("APNs request error:", err);
      }
    }));
  } catch (err) {
    console.error("sendPush error:", err);
  }
}

// APNs wants the provider token reused: keep it about 50 minutes in memory
// (it is valid for an hour and must not be regenerated more than every 20).
let cached: { jwt: string; at: number } | null = null;

async function providerToken(teamId: string, keyId: string, privateKeyPem: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && now - cached.at < 50 * 60) return cached.jwt;

  const signingInput = `${b64url(JSON.stringify({ alg: "ES256", kid: keyId }))}.${b64url(JSON.stringify({ iss: teamId, iat: now }))}`;
  const pem = privateKeyPem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  // WebCrypto returns the raw r||s signature that JWT ES256 expects.
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput));
  const jwt = `${signingInput}.${b64url(new Uint8Array(signature))}`;
  cached = { jwt, at: now };
  return jwt;
}

function b64url(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
