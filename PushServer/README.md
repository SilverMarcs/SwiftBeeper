# Relay push Worker

A personal Cloudflare Worker that forwards Matrix notifications to APNs. One
shared secret protects device registration and notification preferences; D1
holds your devices, suppressed room IDs with expiry times, and one day of
delivery IDs for retry suppression. There are no Matrix sessions, sync loops,
stored messages, or encryption keys on this service. This folder is independent
of the Xcode project.

Current deployment: <https://relay-push.zabirraihan.workers.dev>. The configured
D1 database holds device registrations and notification preferences. Worker secrets are configured in
Cloudflare; the private registration configuration is stored outside this repo.

## Deploy

From this folder:

```sh
npm ci
npx wrangler login --device
npx wrangler d1 create relay-push-devices
```

For a fresh deployment, copy the returned database ID into `wrangler.jsonc`.
Then create the table and set the Worker secrets:

```sh
npx wrangler d1 execute relay-push-devices --remote --file schema.sql
npx wrangler secret put PUSH_SECRET
npx wrangler secret put APNS_KEY_ID
npx wrangler secret put APNS_TEAM_ID
npx wrangler secret put APNS_PRIVATE_KEY < /absolute/path/to/AuthKey.p8
npm run deploy
```

Use a random value of at least 32 characters for `PUSH_SECRET`, such as the output
of `openssl rand -hex 32`. Save the same value privately for app registration.
`APNS_PRIVATE_KEY` is the complete Apple `.p8` file. Secrets belong in Wrangler,
never in source control. `APNS_TOPIC` is the app bundle ID. Keep the configured
`sandbox` environment for development-signed tokens; change it to `production`
for distribution builds.

The deploy command prints your public HTTPS Worker URL. `/health` returns
`{"ok":true}`; it is a liveness check, not a credential or delivery check.

## How registration and delivery work

1. The app obtains an APNs token and chooses a persistent installation ID.
2. It calls `PUT /devices/{installationID}` with
   `Authorization: Bearer <PUSH_SECRET>` and `{"token":"APNs-token"}`.
3. The Worker returns a random `pushkey`, `app_id`, and `gatewayPath`. Repeating
   registration updates the APNs token while preserving the pushkey.
4. Using its existing Beeper Matrix login, the app registers an HTTP pusher via
   `POST /_matrix/client/v3/pushers/set`:

```json
{
  "pushkey": "returned-pushkey",
  "kind": "http",
  "app_id": "returned-app_id",
  "app_display_name": "Relay",
  "device_display_name": "My iPhone",
  "lang": "en",
  "append": true,
  "data": {
    "url": "https://your-worker.workers.dev/_matrix/push/v1/notify"
  }
}
```

Matrix then posts events to that URL. The random device pushkey authorizes
forwarding; Matrix does not send the registration secret. The Worker sends APNs
an alert with `mutable-content: 1`, the room ID (`chatID`), and event ID
(`messageID`), and a boolean `isMention`. It stores no message content. Unknown or expired devices are
rejected; transient APNs errors return a retryable error. Unread-count-only
updates are ignored because opening Relay clears its local badge.

`PUT /notification-preferences`, authenticated with the same shared secret, replaces the
single account's suppression list with `{"rooms":[{"roomID":"!room:server","blockedUntil":-1}]}`.
Negative expiry means forever; positive expiry is Unix milliseconds. The Worker
checks this list before both Matrix callbacks and direct notifications reach
APNs, so ordinary messages in a suppressed room produce no alert, sound, or badge. Expired mutes stop
matching automatically, with no scheduled job.

Relay combines muted chats with Beeper's archived and Low Priority chats. In
Relay, both of those inbox categories appear under Archive. Muted chats retain
their expiry; archived and Low Priority chats are blocked until removed from
that category. Replies and keywords remain suppressed, but **personal mentions
of the signed-in user bypass these blocks**. Room-wide mentions do not bypass
muting. A mention remains the original message, with the same event ID and one
notification; it is not an additional notification or message. Both gateway
entry points share per-device event deduplication, with APNs collapse IDs as a
further safeguard. Transient failures release their lease for Matrix to retry.
It uploads once per app launch and after preference changes, skipping unchanged data
within that launch. Changes made in another app reach the Worker when Relay
next receives them through Matrix sync. Existing Matrix push rules still apply
upstream. No Matrix credentials are sent to the Worker.

Relay installs the account-level `com.silvermarcs.relay.mention` override ahead
of room mutes, below the global master switch. It uses `m.mentions.user_ids`,
requests the normal message push, and adds an exact mention tweak. Matrix push
rules are shared with other clients on the same account. The app checks the
rule at launch and when the suppression list changes. It does not unmute or
unarchive chats. Launch the updated app on each device to register the new
pusher format and apply the rule.

The `event_id_only` format discards push-rule tweaks, so updated pushers use the
standard Matrix callback. That callback can include sender/room metadata and
unencrypted message content. The Worker ignores this content and never stores,
logs, or forwards it to APNs. It reads only event/room/device IDs and the exact
mention tweak; generic `highlight` or high priority is not proof of a mention.
Older event-ID-only pushers still work for ordinary notifications.

Unencrypted Matrix messages and Beeper bridge events with visible mention
metadata support this server-side exception. Fully encrypted Matrix events
whose mention metadata is also encrypted cannot be classified by the server.
Reliable mention-only alerts for those muted rooms require on-device filtering
with Apple's separately approved notification-filtering entitlement. Relay
does not currently have that entitlement, and does not bypass muting for all
encrypted events as a workaround. When the extension decrypts a delivered
message, its preview uses the real recipients to identify it as a mention.

The app requests notification permission after login and registers automatically
at launch or when returning to the foreground. Settings has one Notifications
row with Allow when permission is missing and Reconnect once allowed.
Sign-out removes this installation's
Matrix pusher and Worker registration. Other apps' pushers are preserved.

Personal builds read `App/Configuration/PushConfiguration.private.json`, an
ignored resource containing `serverURL` and `registrationSecret`. Xcode includes
it directly; no project generator or configuration script is required. The
registration secret matches the Worker's `PUSH_SECRET`. Apple signing must use
a provisioning profile with the Push Notifications capability.

The app's Notification Service Extension prepares previews on iPhone, iPad,
and Mac. Relay shares its existing Matrix login and backup decryption key only
with that signed extension through Keychain. The extension fetches the notified
event, checks the backup version, retrieves that session's encrypted key, and
optionally looks up the sender's display name. It does not start sync, open the
app database, or maintain a second Olm account. The Worker receives no Matrix
credentials or decryption keys.

Open Relay once after installation or login to enable previews. Keychain access
is available after the device's first unlock following a restart. If the key
has not reached Beeper's backup yet, the device is offline, or the extension
times out, the original “New message” alert is the fallback.

`DELETE /devices/{installationID}` uses the shared bearer secret. On logout, also
remove the Matrix pusher using the app's authenticated Matrix session.

For trusted callers that already have notification text, `POST /notify` accepts
the same bearer secret and
`{"title":"Sender","body":"Message","chatID":"room","messageID":"event"}`.
Optional `deviceID` selects one of your installations; otherwise it sends to all
your registered devices. Optional `isMention: true` identifies a personal
mention and bypasses room suppression. Use the original chat and message IDs
so a direct send and a Matrix callback cannot become two notifications.

## Local development

Create an ignored `.dev.vars` file containing `PUSH_SECRET`, `APNS_KEY_ID`,
`APNS_TEAM_ID`, and `APNS_PRIVATE_KEY` (PEM with escaped `\n` newlines). Then:

```sh
npx wrangler d1 execute relay-push-devices --local --file schema.sql
npm run dev
```

`npm run build` bundles without deploying. Local enrollment and database access
can be checked with Wrangler; verify real APNs delivery on the deployed Worker
and an actual device.
