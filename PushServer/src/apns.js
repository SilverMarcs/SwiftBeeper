const encoder = new TextEncoder();
const MAX_PAYLOAD_BYTES = 4096;
// The provider token is reused until shortly before Apple's one-hour limit,
// and rebuilt when the configured credentials change.
let cachedToken;

function base64url(bytes) {
  return btoa(String.fromCharCode(...new Uint8Array(bytes)))
    .replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

async function providerToken(env) {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken?.pem === env.APNS_PRIVATE_KEY && cachedToken.keyID === env.APNS_KEY_ID &&
      cachedToken.teamID === env.APNS_TEAM_ID && now < cachedToken.expires) return cachedToken.token;
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
  cachedToken = { pem: env.APNS_PRIVATE_KEY, keyID: env.APNS_KEY_ID, teamID: env.APNS_TEAM_ID, expires: now + 3000, token };
  return token;
}

// The alert the app's notification service extension replaces with a preview.
export function notification(title, body, chatID = "", messageID = "", isMention = false) {
  return {
    aps: { alert: { title, body }, sound: "default", badge: 1, "mutable-content": 1, "thread-id": chatID },
    chatID, messageID, isMention,
  };
}

// Both Matrix callbacks and trusted direct sends use the same event identity.
// A mention changes eligibility, never creates a second notification. Keep a
// short lease while sending so concurrent callbacks cannot both send it.
export async function deliver(env, device, payload) {
  if (!payload.chatID || !payload.messageID) return send(env, device, payload);
  const now = Date.now();
  const claim = crypto.randomUUID();
  // Retain only a day's deduplication IDs; no message text enters this table.
  await env.DEVICES.prepare("DELETE FROM notification_deliveries WHERE claimed_until < ?")
    .bind(now - 86400000).run();
  const acquired = await env.DEVICES.prepare(`
    INSERT INTO notification_deliveries (device_id, room_id, event_id, claim, claimed_until, sent)
    VALUES (?, ?, ?, ?, ?, 0)
    ON CONFLICT(device_id, room_id, event_id) DO UPDATE
      SET claim = excluded.claim, claimed_until = excluded.claimed_until
      WHERE notification_deliveries.sent = 0 AND notification_deliveries.claimed_until <= ?
    RETURNING claim
  `).bind(device.id, payload.chatID, payload.messageID, claim, now + 60000, now).first();
  if (!acquired) {
    const existing = await env.DEVICES.prepare(`
      SELECT sent FROM notification_deliveries WHERE device_id = ? AND room_id = ? AND event_id = ?
    `).bind(device.id, payload.chatID, payload.messageID).first();
    // An in-flight attempt must be retried if it fails, rather than silently
    // acknowledged. A successful earlier delivery is already complete.
    return existing?.sent === 1 ? "sent" : "failed";
  }
  try {
    const result = await send(env, device, payload);
    if (result === "sent") {
      await env.DEVICES.prepare("UPDATE notification_deliveries SET sent = 1 WHERE claim = ?")
        .bind(claim).run();
    } else {
      await env.DEVICES.prepare("DELETE FROM notification_deliveries WHERE claim = ?").bind(claim).run();
    }
    return result;
  } catch (error) {
    await env.DEVICES.prepare("DELETE FROM notification_deliveries WHERE claim = ?").bind(claim).run();
    throw error;
  }
}

// Sends one alert and returns "sent", "expired" (the device was removed) or "failed".
async function send(env, device, payload) {
  const body = JSON.stringify(payload);
  if (encoder.encode(body).length > MAX_PAYLOAD_BYTES) throw new Error("APNs payload exceeds 4096 bytes");
  const environment = env.APNS_ENVIRONMENT;
  if (environment !== "sandbox" && environment !== "production") throw new Error("Invalid APNs environment");
  const host = environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const headers = {
    authorization: `bearer ${await providerToken(env)}`, "apns-topic": env.APNS_TOPIC,
    "apns-push-type": "alert", "apns-priority": "10", "apns-expiration": "0", "content-type": "application/json",
  };
  if (payload.messageID) {
    // Repeated pushes for one message replace each other on the device.
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
