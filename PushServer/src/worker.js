import { deliver, notification } from "./apns.js";

const MATRIX_GATEWAY_PATH = "/_matrix/push/v1/notify";

class HTTPError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

function json(value, status = 200) {
  return Response.json(value, { status, headers: { "Cache-Control": "no-store" } });
}

// Reads a JSON object body of at most `maximum` bytes.
async function readJSON(request, maximum = 65536) {
  const reader = request.body?.getReader();
  if (!reader) throw new HTTPError(400, "JSON body required");
  const chunks = [];
  let length = 0;
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    length += value.length;
    if (length > maximum) { await reader.cancel(); throw new HTTPError(413, "Request too large"); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  try {
    const value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error();
    return value;
  } catch { throw new HTTPError(400, "Invalid JSON body"); }
}

// Checks the shared registration secret. Hashing both sides first keeps the
// comparison constant-time regardless of length.
async function authorize(request, env) {
  if (typeof env.PUSH_SECRET !== "string" || env.PUSH_SECRET.trim().length < 32) throw new HTTPError(503, "Registration secret is not configured");
  const encoder = new TextEncoder();
  const expected = await crypto.subtle.digest("SHA-256", encoder.encode(`Bearer ${env.PUSH_SECRET}`));
  const actual = await crypto.subtle.digest("SHA-256", encoder.encode(request.headers.get("Authorization") ?? ""));
  if (!crypto.subtle.timingSafeEqual(actual, expected)) throw new HTTPError(401, "Unauthorized");
}

function isBoundedString(value, maximum) { return typeof value === "string" && value.length <= maximum; }
function optionalBoundedString(value, maximum) { return value === undefined || isBoundedString(value, maximum); }
function randomKey() { return [...crypto.getRandomValues(new Uint8Array(32))].map(value => value.toString(16).padStart(2, "0")).join(""); }

// PUT /notification-preferences replaces the whole suppression list.
async function updateNotificationPreferences(request, env) {
  const input = await readJSON(request, 1048576);
  if (!Array.isArray(input.rooms) || input.rooms.length > 10000) throw new HTTPError(400, "Invalid notification preferences");
  const rooms = new Map();
  for (const room of input.rooms) {
    if (!room || !isBoundedString(room.roomID, 256) || !room.roomID.startsWith("!") ||
        !Number.isSafeInteger(room.blockedUntil) || room.blockedUntil === 0) throw new HTTPError(400, "Invalid blocked room");
    rooms.set(room.roomID, room.blockedUntil);
  }
  const statements = [env.DEVICES.prepare("DELETE FROM notification_blocks")];
  const entries = [...rooms];
  // D1 batches are atomic. Keep each insert below SQLite's parameter limit.
  for (let i = 0; i < entries.length; i += 40) {
    const chunk = entries.slice(i, i + 40);
    statements.push(env.DEVICES.prepare(`INSERT INTO notification_blocks (room_id, blocked_until) VALUES ${chunk.map(() => "(?, ?)").join(",")}`)
      .bind(...chunk.flat()));
  }
  await env.DEVICES.batch(statements);
  return json({ ok: true });
}

// A negative expiry blocks forever; a positive one is Unix milliseconds.
async function isBlocked(env, roomID) {
  if (!roomID) return false;
  return !!await env.DEVICES.prepare("SELECT 1 FROM notification_blocks WHERE room_id = ? AND (blocked_until < 0 OR blocked_until > ?) LIMIT 1")
    .bind(roomID, Date.now()).first();
}

// PUT /devices/{id} stores the APNs token, keeping an existing pushkey.
async function register(request, env, id) {
  const input = await readJSON(request);
  if (!isBoundedString(input.token, 256) || !/^[0-9a-f]{32,256}$/i.test(input.token) || input.token.length % 2) throw new HTTPError(400, "Invalid APNs token");
  const device = await env.DEVICES.prepare(`
    INSERT INTO devices (id, pushkey, token) VALUES (?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET token = excluded.token RETURNING pushkey
  `).bind(id, randomKey(), input.token.toLowerCase()).first();
  return json({ pushkey: device.pushkey, app_id: env.APNS_TOPIC, gatewayPath: MATRIX_GATEWAY_PATH });
}

async function unregister(env, id) {
  await env.DEVICES.prepare("DELETE FROM devices WHERE id = ?").bind(id).run();
  return json({ ok: true });
}

// The standard Matrix callback carries our exact mention tweak. Generic
// highlight/high priority can mean replies or encrypted traffic, so neither
// bypasses a block. Message content is ignored and never logged or stored.
async function matrixPush(request, env) {
  const { notification: incoming } = await readJSON(request, 1048576);
  if (!incoming || !Array.isArray(incoming.devices) || incoming.devices.length > 100 ||
      !optionalBoundedString(incoming.event_id, 256) || !optionalBoundedString(incoming.room_id, 256)) throw new HTTPError(400, "Invalid Matrix notification");
  const rejected = [];
  let failed = false;
  const seen = new Set();
  const blocked = await isBlocked(env, incoming.room_id);
  for (const requested of incoming.devices) {
    if (!requested || !isBoundedString(requested.pushkey, 512)) throw new HTTPError(400, "Invalid pushkey");
    if (seen.has(requested.pushkey)) continue;
    seen.add(requested.pushkey);
    const device = requested.app_id === env.APNS_TOPIC && /^[0-9a-f]{64}$/.test(requested.pushkey)
      ? await env.DEVICES.prepare("SELECT id, token FROM devices WHERE pushkey = ?").bind(requested.pushkey).first() : null;
    if (!device) { rejected.push(requested.pushkey); continue; }
    // Ignore unread-count-only updates: opening Relay clears the local badge.
    const isMention = requested.tweaks?.["com.silvermarcs.relay.mention"] === true;
    if (!incoming.event_id || !incoming.room_id || (blocked && !isMention)) continue;
    const result = await deliver(env, device, notification("Relay", isMention ? "You were mentioned" : "New message", incoming.room_id, incoming.event_id, isMention));
    if (result === "expired") rejected.push(requested.pushkey);
    if (result === "failed") failed = true;
  }
  if (failed) throw new HTTPError(502, "APNs delivery failed; retry");
  return json({ rejected });
}

// POST /notify sends caller-provided text to one or all registered devices.
async function directPush(request, env) {
  const input = await readJSON(request);
  if (!isBoundedString(input.title, 200) || !input.title || !isBoundedString(input.body, 2000) || !input.body ||
      !optionalBoundedString(input.chatID, 256) || !optionalBoundedString(input.messageID, 256) ||
      !optionalBoundedString(input.deviceID, 128) ||
      (input.isMention !== undefined && typeof input.isMention !== "boolean")) throw new HTTPError(400, "Invalid notification");
  const isMention = input.isMention === true;
  const payload = notification(input.title, input.body, input.chatID, input.messageID, isMention);
  if (new TextEncoder().encode(JSON.stringify(payload)).length > 4096) throw new HTTPError(400, "Notification exceeds APNs limit");
  if (!isMention && await isBlocked(env, input.chatID)) return json({ sent: 0, failed: 0, suppressed: true });
  const { results } = input.deviceID
    ? await env.DEVICES.prepare("SELECT id, token FROM devices WHERE id = ?").bind(input.deviceID).all()
    : await env.DEVICES.prepare("SELECT id, token FROM devices").all();
  if (!results.length) throw new HTTPError(404, "No registered devices");
  let sent = 0, failed = 0;
  for (const device of results) {
    if (await deliver(env, device, payload) === "sent") sent++;
    else failed++;
  }
  return json({ sent, failed }, failed ? 502 : 200);
}

async function route(request, env) {
  const { method } = request;
  const path = new URL(request.url).pathname;
  if (method === "GET" && path === "/health") return json({ ok: true });
  if (method === "POST" && path === MATRIX_GATEWAY_PATH) return matrixPush(request, env);
  if (method === "PUT" && path === "/notification-preferences") {
    await authorize(request, env);
    return updateNotificationPreferences(request, env);
  }
  if (method === "POST" && path === "/notify") {
    await authorize(request, env);
    return directPush(request, env);
  }
  const device = /^\/devices\/([A-Za-z0-9_-]{1,128})$/.exec(path);
  if (device && (method === "PUT" || method === "DELETE")) {
    await authorize(request, env);
    return method === "PUT" ? register(request, env, device[1]) : unregister(env, device[1]);
  }
  return json({ error: "Not found" }, 404);
}

export default {
  async fetch(request, env) {
    try {
      return await route(request, env);
    } catch (error) {
      if (error instanceof HTTPError) return json({ error: error.message }, error.status);
      console.error("Push request failed", error.name);
      return json({ error: "Push service unavailable" }, 503);
    }
  },
};
