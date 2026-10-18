const encoder = new TextEncoder();
let cached;

function base64url(bytes) {
  return btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

async function bearer(env) {
  const now = Math.floor(Date.now() / 1000);
  if (cached?.pem === env.APNS_PRIVATE_KEY && cached.keyID === env.APNS_KEY_ID &&
      cached.teamID === env.APNS_TEAM_ID && now < cached.expires) return cached.token;
  const pem = env.APNS_PRIVATE_KEY?.replaceAll("\\n", "\n");
  if (!pem || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) throw new Error("APNs credentials are missing");
  const encoded = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s/g, "");
  const key = await crypto.subtle.importKey("pkcs8", Uint8Array.from(atob(encoded), char => char.charCodeAt(0)),
    { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = base64url(encoder.encode(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID })));
  const claims = base64url(encoder.encode(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: now })));
  const unsigned = `${header}.${claims}`;
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, encoder.encode(unsigned));
  const token = `${unsigned}.${base64url(signature)}`;
  cached = { pem: env.APNS_PRIVATE_KEY, keyID: env.APNS_KEY_ID, teamID: env.APNS_TEAM_ID, expires: now + 3000, token };
  return token;
}

export function notification(title, body, chatID = "", messageID = "") {
  return {
    aps: { alert: { title, body }, sound: "default", badge: 1, "mutable-content": 1, "thread-id": chatID },
    chatID, messageID,
  };
}

export async function deliver(env, device, payload) {
  const body = JSON.stringify(payload);
  if (encoder.encode(body).length > 4096) throw new Error("APNs payload exceeds 4096 bytes");
  const environment = env.APNS_ENVIRONMENT;
  if (environment !== "sandbox" && environment !== "production") throw new Error("Invalid APNs environment");
  const host = environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const headers = {
    authorization: `bearer ${await bearer(env)}`, "apns-topic": env.APNS_TOPIC,
    "apns-push-type": "alert", "apns-priority": "10", "apns-expiration": "0", "content-type": "application/json",
  };
  if (payload.messageID) {
    const hash = await crypto.subtle.digest("SHA-256", encoder.encode(`${payload.chatID}\0${payload.messageID}`));
    headers["apns-collapse-id"] = base64url(hash);
  }
  const response = await fetch(`https://${host}/3/device/${device.token}`, {
    method: "POST", headers, body, redirect: "manual", signal: AbortSignal.timeout(15000),
  });
  if (response.ok) return "sent";
  const reason = (await response.json().catch(() => ({}))).reason;
  if (response.status === 410 || (response.status === 400 && reason === "BadDeviceToken")) {
    // A token may have rotated while this request was in flight.
    const removed = await env.DEVICES.prepare("DELETE FROM devices WHERE id = ? AND token = ? RETURNING id")
      .bind(device.id, device.token).first();
    return removed ? "expired" : "failed";
  }
  console.error("APNs delivery failed", response.status, reason ?? "unknown");
  return "failed";
}
