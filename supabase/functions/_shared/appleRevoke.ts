// Revokes a Sign in with Apple grant when an account is deleted (App Store
// guideline 5.1.1(v)). Needs these secrets (Apple Developer > Keys, with Sign
// in with Apple enabled):
//   APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY (contents of the .p8)
//   APPLE_CLIENT_ID (optional, defaults to the app's bundle id)
// The app obtains a fresh authorization code right before deletion; we
// exchange it for a refresh token and revoke that. Never throws. Returns
// true if Apple confirmed the revocation.

const BUNDLE_ID = "com.goldenroadgames.carddrop";

export async function revokeAppleAccess(authorizationCode: string): Promise<boolean> {
  const teamId = Deno.env.get("APPLE_TEAM_ID");
  const keyId = Deno.env.get("APPLE_KEY_ID");
  const privateKey = Deno.env.get("APPLE_PRIVATE_KEY");
  const clientId = Deno.env.get("APPLE_CLIENT_ID") ?? BUNDLE_ID;
  if (!teamId || !keyId || !privateKey) {
    console.error("revokeAppleAccess: APPLE_TEAM_ID / APPLE_KEY_ID / APPLE_PRIVATE_KEY not set, skipping");
    return false;
  }

  try {
    const clientSecret = await makeClientSecret(teamId, keyId, privateKey, clientId);

    const tokenRes = await fetch("https://appleid.apple.com/auth/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        code: authorizationCode,
        grant_type: "authorization_code",
      }),
    });
    if (!tokenRes.ok) {
      console.error("Apple token exchange failed:", tokenRes.status, await tokenRes.text());
      return false;
    }
    const tokens = await tokenRes.json();
    const token = tokens.refresh_token ?? tokens.access_token;
    if (!token) return false;

    const revokeRes = await fetch("https://appleid.apple.com/auth/revoke", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        token,
        token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
      }),
    });
    if (!revokeRes.ok) {
      console.error("Apple revoke failed:", revokeRes.status, await revokeRes.text());
      return false;
    }
    return true;
  } catch (err) {
    console.error("revokeAppleAccess error:", err);
    return false;
  }
}

async function makeClientSecret(
  teamId: string,
  keyId: string,
  privateKeyPem: string,
  clientId: string,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: keyId };
  const payload = {
    iss: teamId,
    iat: now,
    exp: now + 300,
    aud: "https://appleid.apple.com",
    sub: clientId,
  };
  const signingInput = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;

  const pem = privateKeyPem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  // WebCrypto returns the raw r||s signature that JWT ES256 expects.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${b64url(new Uint8Array(signature))}`;
}

function b64url(input: string | Uint8Array): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
