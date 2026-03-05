# Beeper Desktop API Specifications

This file contains the complete API specifications for the Beeper Desktop API,
including both the HTTP REST API (OpenAPI) and the WebSocket live event stream.

---

# HTTP REST API

- **Base URL:** `http://localhost:23373`
- **OpenAPI Version:** 3.1.0
- **API Version:** 0.2.0

## Authentication

All endpoints require Bearer token authentication:
```
Authorization: Bearer <your_token>
```

OAuth2 PKCE flow is also supported:
- **Authorization URL:** `http://localhost:23373/oauth/authorize`
- **Token URL:** `http://localhost:23373/oauth/token`
- **Scopes:** `read` (read access), `write` (write access)

## Schemas

### Error

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `message` | `string` | Yes | Error message |
| `code` | `string` | Yes | Machine-readable error code |
| `details` | `` | No | Additional error details for debugging |

### ChatID

Unique identifier of the chat.

### AccountID

Account ID this resource belongs to.

### Cursor

Opaque pagination cursor; do not inspect. Use together with 'direction'.

### Direction

Pagination direction used with 'cursor': 'before' fetches older results, 'after' fetches newer results. Defaults to 'before' when only 'cursor' is provided.

### User

User the account belongs to.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | Yes | Stable Beeper user ID. Use as the primary key when referencing a person. |
| `username` | `string` | No | Human-readable handle if available (e.g., '@alice'). May be network-specific and not globally unique. |
| `phoneNumber` | `string` | No | User's phone number in E.164 format (e.g., '+14155552671'). Omit if unknown. |
| `email` | `string` | No | Email address if known. Not guaranteed verified. |
| `fullName` | `string` | No | Display name as shown in clients (e.g., 'Alice Example'). May include emojis. |
| `imgURL` | `string` | No | Avatar image URL if available. May be temporary or local-only to this device; download promptly if durable access is needed. |
| `cannotMessage` | `boolean` | No | True if Beeper cannot initiate messages to this user (e.g., blocked, network restriction, or no DM path). The user may still message you. |
| `isSelf` | `boolean` | No | True if this user represents the authenticated account's own identity. |

### Account

A chat account added to Beeper

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `accountID` | `string` | Yes | Chat account added to Beeper. Use this to route account-scoped actions. |
| `user` | `User` | Yes |  |

### GetAccountsOutput

Connected accounts the user can act through. Includes accountID and user identity.

### Attachment

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | No | Attachment identifier (typically an mxc:// URL). Use with /v1/assets/download to get a local file path. |
| `type` | `string` | Yes | Attachment type. Enum: `unknown`, `img`, `video`, `audio` |
| `srcURL` | `string` | No | Public URL or local file path to fetch the asset. May be temporary or local-only to this device; download promptly if durable access is needed. |
| `mimeType` | `string` | No | MIME type if known (e.g., 'image/png'). |
| `fileName` | `string` | No | Original filename if available. |
| `fileSize` | `number` | No | File size in bytes if known. |
| `isGif` | `boolean` | No | True if the attachment is a GIF. |
| `isSticker` | `boolean` | No | True if the attachment is a sticker. |
| `isVoiceNote` | `boolean` | No | True if the attachment is a voice note. |
| `duration` | `number` | No | Duration in seconds (audio/video). |
| `posterImg` | `string` | No | Preview image URL for video attachments (poster frame). May be temporary or local-only to this device; download promptly if durable access is needed. |
| `size` | `object` | No | Pixel dimensions of the attachment: width/height in px. |

### Reaction

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | Yes | Reaction ID, typically ${participantID}${reactionKey} if multiple reactions allowed, or just participantID otherwise. |
| `reactionKey` | `string` | Yes | The reaction key: an emoji (😄), a network-specific key, or a shortcode like "smiling-face". |
| `imgURL` | `string` | No | URL to the reaction's image. May be temporary or local-only to this device; download promptly if durable access is needed. |
| `participantID` | `string` | Yes | User ID of the participant who reacted. |
| `emoji` | `boolean` | No | True if the reactionKey is an emoji. |

### Message

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | Yes | Message ID. |
| `chatID` | `string` | Yes | Unique identifier of the chat. |
| `accountID` | `string` | Yes | Beeper account ID the message belongs to. |
| `senderID` | `string` | Yes | Sender user ID. |
| `senderName` | `string` | No | Resolved sender display name (impersonator/full name/username/participant name). |
| `timestamp` | `string` | Yes | Message timestamp. |
| `sortKey` | `string` | Yes | A unique, sortable key used to sort messages. |
| `type` | `string` | No | Message content type. Useful for distinguishing reactions, media messages, and state events from regular text messages. Enum: `TEXT`, `NOTICE`, `IMAGE`, `VIDEO`, `VOICE`, `AUDIO`, `FILE`, `STICKER`, `LOCATION`, `REACTION` |
| `text` | `string` | No | Plain-text body if present. May include a JSON fallback with text entities for rich messages. |
| `isSender` | `boolean` | No | True if the authenticated user sent the message. |
| `attachments` | `[Attachment]` | No | Attachments included with this message, if any. |
| `isUnread` | `boolean` | No | True if the message is unread for the authenticated user. May be omitted. |
| `linkedMessageID` | `string` | No | ID of the message this is a reply to, if any. |
| `reactions` | `[Reaction]` | No | Reactions to the message, if any. |

### Chat

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | Yes | Unique identifier of the chat across Beeper. |
| `localChatID` | `string` | No | Local chat ID specific to this Beeper Desktop installation. |
| `accountID` | `string` | Yes | Account ID this chat belongs to. |
| `title` | `string` | Yes | Display title of the chat as computed by the client/server. |
| `type` | `string` | Yes | Chat type: 'single' for direct messages, 'group' for group chats. Enum: `single`, `group` |
| `participants` | `object` | Yes | Chat participants information. |
| `lastActivity` | `string` | No | Timestamp of last activity. |
| `unreadCount` | `integer` | Yes | Number of unread messages. |
| `lastReadMessageSortKey` | `string` | No | Last read message sortKey. |
| `isArchived` | `boolean` | No | True if chat is archived. |
| `isMuted` | `boolean` | No | True if chat notifications are muted. |
| `isPinned` | `boolean` | No | True if chat is pinned. |

### SearchMessagesOutput

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `items` | `[Message]` | Yes | Messages matching the query and filters. |
| `chats` | `object` | Yes | Map of chatID -> chat details for chats referenced in items. |
| `hasMore` | `boolean` | Yes | True if additional results can be fetched using the provided cursors. |
| `oldestCursor` | `string` | Yes | Cursor for fetching older results (use with direction='before'). Opaque string; do not inspect. |
| `newestCursor` | `string` | Yes | Cursor for fetching newer results (use with direction='after'). Opaque string; do not inspect. |

### SearchChatsOutput

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `items` | `[Chat]` | Yes | Chats matching the filters. |
| `hasMore` | `boolean` | Yes | True if additional results can be fetched using the provided cursors. |
| `oldestCursor` | `string` | Yes | Cursor for fetching older results (use with direction='before'). Opaque string; do not inspect. |
| `newestCursor` | `string` | Yes | Cursor for fetching newer results (use with direction='after'). Opaque string; do not inspect. |

### SearchContactsOutput

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `items` | `[any]` | Yes |  |

### ListContactsOutput

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `items` | `[any]` | Yes | Merged contacts for the selected account. |
| `hasMore` | `boolean` | Yes | True if additional results can be fetched using cursors. |
| `oldestCursor` | `string` | Yes | Cursor for fetching older results (use with direction='before'). Opaque string; do not inspect. |
| `newestCursor` | `string` | Yes | Cursor for fetching newer results (use with direction='after'). Opaque string; do not inspect. |

### UnifiedSearchOutput

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `results` | `object` | Yes |  |

### FocusAppOutput

Response indicating successful app focus action.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `success` | `boolean` | Yes | Whether the app was successfully opened/focused. |

### FocusAppInput

Focus Beeper Desktop and optionally navigate to a specific chat, message, or pre-fill draft text and attachment.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `chatID` | `string` | No | Optional Beeper chat ID (or local chat ID) to focus after opening the app. If omitted, only opens/focuses the app. |
| `messageID` | `string` | No | Optional message ID. Jumps to that message in the chat when opening. |
| `draftText` | `string` | No | Optional draft text to populate in the message input field. |
| `draftAttachmentPath` | `string` | No | Optional draft attachment path to populate in the message input field. |

### ListChatsOutput

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `items` | `[any]` | Yes | Chats ordered by last activity timestamp (most recent first). |
| `hasMore` | `boolean` | Yes | True if additional results can be fetched using the provided cursors. |
| `oldestCursor` | `string` | Yes | Cursor for fetching older results (use with direction='before'). Opaque string; do not inspect. |
| `newestCursor` | `string` | Yes | Cursor for fetching newer results (use with direction='after'). Opaque string; do not inspect. |

### CreateChatOutput

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `chatID` | `string` | Yes | Newly created chat ID. |
| `status` | `string` | No | Only returned in start mode. 'existing' means an existing chat was reused; 'created' means a new chat was created. Enum: `existing`, `created` |

### CreateChatInput

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `accountID` | `string` | Yes | Account to create or start the chat on. |
| `mode` | `string` | No | Operation mode. Defaults to 'create' when omitted. Enum: `create`, `start` |
| `type` | `string` | No | Required when mode='create'. 'single' requires exactly one participantID; 'group' supports multiple participants and optional title. Enum: `single`, `group` |
| `participantIDs` | `[string]` | No | Required when mode='create'. User IDs to include in the new chat. |
| `title` | `string` | No | Optional title for group chats when mode='create'; ignored for single chats on most platforms. |
| `user` | `object` | No | Required when mode='start'. Merged user-like contact payload used to resolve the best identifier. |
| `messageText` | `string` | No | Optional first message content if the platform requires it to create the chat. |
| `allowInvite` | `boolean` | No | Whether invite-based DM creation is allowed when required by the platform. Used for mode='start'. |

### ListMessagesOutput

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `items` | `[Message]` | Yes | Messages from the chat, sorted by timestamp. Use message.sortKey as the cursor for pagination and treat it as an opaque value. |
| `hasMore` | `boolean` | Yes | True if additional results can be fetched. |

### SendMessageOutput

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `chatID` | `string` | Yes | Unique identifier of the chat. |
| `pendingMessageID` | `string` | Yes | Pending message ID |

### MessageAttachmentType

Special attachment type (gif, voiceNote, sticker). If omitted, auto-detected from mimeType

### MessageAttachmentInput

Single attachment to send with the message

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `uploadID` | `string` | Yes | Upload ID from uploadAsset endpoint. Required to reference uploaded files. |
| `mimeType` | `string` | No | MIME type (optional override of cached value) |
| `fileName` | `string` | No | Filename (optional override of cached value) |
| `size` | `object` | No | Dimensions (optional override of cached value) |
| `duration` | `number` | No | Duration in seconds (optional override of cached value) |
| `type` | `MessageAttachmentType` | No |  |

### EditMessageOutput

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `chatID` | `string` | Yes | Unique identifier of the chat. |
| `messageID` | `string` | Yes | Message ID. |
| `success` | `boolean` | Yes | Whether the message was successfully edited |

### AddReactionOutput

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `success` | `boolean` | Yes | Whether the reaction was successfully added Enum: `True` |
| `chatID` | `string` | Yes | Unique identifier of the chat. |
| `messageID` | `string` | Yes | Message ID. |
| `reactionKey` | `string` | Yes | Reaction key that was added |
| `transactionID` | `string` | Yes | Transaction ID used for the reaction event |

### RemoveReactionOutput

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `success` | `boolean` | Yes | Whether the reaction was successfully removed Enum: `True` |
| `chatID` | `string` | Yes | Unique identifier of the chat. |
| `messageID` | `string` | Yes | Message ID. |
| `reactionKey` | `string` | Yes | Reaction key that was removed |

### DownloadAssetOutput

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `srcURL` | `string` | No | Local file URL to the downloaded asset. |
| `error` | `string` | No | Error message if the download failed. |

### DownloadAssetInput

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `url` | `string` | Yes | Matrix content URL (mxc:// or localmxc://) for the asset to download. |

### UploadAssetOutput

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `uploadID` | `string` | No | Unique upload ID for this asset |
| `srcURL` | `string` | No | Local file URL (file://) for the uploaded asset |
| `fileName` | `string` | No | Resolved filename |
| `mimeType` | `string` | No | Detected or provided MIME type |
| `fileSize` | `number` | No | File size in bytes |
| `width` | `number` | No | Width in pixels (images/videos) |
| `height` | `number` | No | Height in pixels (images/videos) |
| `duration` | `number` | No | Duration in seconds (audio/videos) |
| `error` | `string` | No | Error message if upload failed |

### UploadAssetMultipart

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `file` | `string` | Yes | The file to upload (max 500 MB). |
| `fileName` | `string` | No | Original filename. Defaults to the uploaded file name if omitted |
| `mimeType` | `string` | No | MIME type. Auto-detected from magic bytes if omitted |

### UploadAssetInput

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `content` | `string` | Yes | Base64-encoded file content (max ~500MB decoded) |
| `fileName` | `string` | No | Original filename. Generated if omitted |
| `mimeType` | `string` | No | MIME type. Auto-detected from magic bytes if omitted |

### ConnectInfoOutput

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `app` | `object` | Yes |  |
| `platform` | `object` | Yes |  |
| `server` | `object` | Yes |  |
| `endpoints` | `object` | Yes |  |

## Endpoints

### Accounts

#### `GET /v1/accounts`

**List connected accounts**

Lists chat accounts across networks (WhatsApp, Telegram, Twitter/X, etc.) actively connected to this Beeper Desktop instance

**Responses:**

- `200`: Request executed successfully
  - Returns: `GetAccountsOutput`
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

### App

#### `GET /v1/search`

**Search**

Returns matching chats, participant name matches in groups, and the first page of messages in one call. Paginate messages via search-messages. Paginate chats via search-chats.

**Parameters:**

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| `query` | query | `string` | Yes | User-typed search text. Literal word matching (non-semantic). |

**Responses:**

- `200`: Request executed successfully
  - Returns: `UnifiedSearchOutput`
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

#### `POST /v1/focus`

**Focus Beeper Desktop app**

Focus Beeper Desktop and optionally navigate to a specific chat, message, or pre-fill draft text and attachment.

**Request Body:** See `FocusAppInput` schema.

**Responses:**

- `200`: Request executed successfully
  - Returns: `FocusAppOutput`
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

#### `POST /v1/assets/download`

**Download an asset**

Download a Matrix asset using its mxc:// or localmxc:// URL to the device running Beeper Desktop and return the local file URL.

**Request Body:** See `DownloadAssetInput` schema.

**Responses:**

- `200`: Request executed successfully
  - Returns: `DownloadAssetOutput`
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

#### `GET /v1/assets/serve`

**Serve an asset**

Stream a file given an mxc://, localmxc://, or file:// URL. Downloads first if not cached. Supports Range requests for seeking in large files.

**Parameters:**

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| `url` | query | `string` | Yes | Asset URL to serve. Accepts mxc://, localmxc://, or file:// URLs. |

**Responses:**

- `204`: Request executed successfully
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

#### `POST /v1/assets/upload`

**Upload an asset**

Upload a file to a temporary location using multipart/form-data. Returns an uploadID that can be referenced when sending messages with attachments.

**Request Body:** See `UploadAssetMultipart` schema.

**Responses:**

- `200`: Request executed successfully
  - Returns: `UploadAssetOutput`
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

#### `POST /v1/assets/upload/base64`

**Upload an asset (base64)**

Upload a file using a JSON body with base64-encoded content. Returns an uploadID that can be referenced when sending messages with attachments. Alternative to the multipart upload endpoint.

**Request Body:** See `UploadAssetInput` schema.

**Responses:**

- `200`: Request executed successfully
  - Returns: `UploadAssetOutput`
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

#### `GET /v1/info`

**Get Connect server info**

Returns app, platform, server, and endpoint discovery metadata for this Beeper Desktop instance.

**Responses:**

- `200`: Connect server info
  - Returns: `ConnectInfoOutput`
- `500`: 

### Messages

#### `GET /v1/messages/search`

**Search messages**

Search messages across chats using Beeper's message index

**Parameters:**

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| `query` | query | `string` | No | Literal word search (non-semantic). Finds messages containing these EXACT words in any order. Use single words users actually type, not concepts or phrases. Example: use "dinner" not "dinner plans", use "sick" not "health issues". If omitted, returns results filtered only by other parameters. |
| `cursor` | query | `string` | No | Opaque pagination cursor; do not inspect. Use together with 'direction'. |
| `direction` | query | `string (after, before)` | No | Pagination direction used with 'cursor': 'before' fetches older results, 'after' fetches newer results. Defaults to 'before' when only 'cursor' is provided. |
| `chatIDs` | query | `array` | No | Limit search to specific chat IDs. |
| `accountIDs` | query | `array` | No | Limit search to specific account IDs. |
| `chatType` | query | `string (group, single)` | No | Filter by chat type: 'group' for group chats, 'single' for 1:1 chats. |
| `mediaTypes` | query | `array` | No | Filter messages by media types. Use ['any'] for any media type, or specify exact types like ['video', 'image']. Omit for no media filtering. |
| `sender` | query | `string` | No | Filter by sender: 'me' (messages sent by the authenticated user), 'others' (messages sent by others), or a specific user ID string (user.id). |
| `dateAfter` | query | `string` | No | Only include messages with timestamp strictly after this ISO 8601 datetime (e.g., '2024-07-01T00:00:00Z' or '2024-07-01T00:00:00+02:00'). |
| `dateBefore` | query | `string` | No | Only include messages with timestamp strictly before this ISO 8601 datetime (e.g., '2024-07-31T23:59:59Z' or '2024-07-31T23:59:59+02:00'). |
| `limit` | query | `integer` | No | Maximum number of messages to return. |
| `excludeLowPriority` | query | `boolean` | No | Exclude messages marked Low Priority by the user. Default: true. Set to false to include all. |
| `includeMuted` | query | `boolean` | No | Include messages in chats marked as Muted by the user, which are usually less important. Default: true. Set to false if the user wants a more refined search. |

**Responses:**

- `200`: Request executed successfully
  - Returns: `SearchMessagesOutput`
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

#### `GET /v1/chats/{chatID}/messages`

**List messages**

List all messages in a chat with cursor-based pagination. Sorted by timestamp.

**Parameters:**

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| `chatID` | path | `string` | Yes | Unique identifier of the chat. |
| `cursor` | query | `string` | No | Opaque pagination cursor; do not inspect. Use together with 'direction'. |
| `direction` | query | `string (after, before)` | No | Pagination direction used with 'cursor': 'before' fetches older results, 'after' fetches newer results. Defaults to 'before' when only 'cursor' is provided. |

**Responses:**

- `200`: Request executed successfully
  - Returns: `ListMessagesOutput`
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

#### `POST /v1/chats/{chatID}/messages`

**Send a message**

Send a text message to a specific chat. Supports replying to existing messages. Returns a pending message ID.

**Parameters:**

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| `chatID` | path | `string` | Yes | Unique identifier of the chat. |

**Request Body** (`application/json`):

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `text` | `string` | No | Text content of the message you want to send. You may use markdown. |
| `replyToMessageID` | `string` | No | Provide a message ID to send this as a reply to an existing message |
| `attachment` | `string` | No |  |

**Responses:**

- `200`: Request executed successfully
  - Returns: `SendMessageOutput`
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

#### `PUT /v1/chats/{chatID}/messages/{messageID}`

**Edit a message**

Edit the text content of an existing message. Messages with attachments cannot be edited.

**Parameters:**

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| `chatID` | path | `string` | Yes | Unique identifier of the chat. |
| `messageID` | path | `string` | Yes | ID of the message to edit |

**Request Body** (`application/json`):

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `text` | `string` | Yes | New text content for the message |

**Responses:**

- `200`: Request executed successfully
  - Returns: `EditMessageOutput`
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

#### `POST /v1/chats/{chatID}/messages/{messageID}/reactions`

**Add a reaction**

Add a reaction to an existing message.

**Parameters:**

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| `chatID` | path | `string` | Yes | Unique identifier of the chat. |
| `messageID` | path | `string` | Yes | ID of the message to add a reaction to |

**Request Body** (`application/json`):

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `reactionKey` | `string` | Yes | Reaction key to add (emoji, shortcode, or custom emoji key) |
| `transactionID` | `string` | No | Optional transaction ID for deduplication and local echo tracking |

**Responses:**

- `200`: Request executed successfully
  - Returns: `AddReactionOutput`
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

#### `DELETE /v1/chats/{chatID}/messages/{messageID}/reactions`

**Remove a reaction**

Remove the authenticated user's reaction from an existing message.

**Parameters:**

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| `chatID` | path | `string` | Yes | Unique identifier of the chat. |
| `messageID` | path | `string` | Yes | ID of the message to remove a reaction from |
| `reactionKey` | query | `string` | Yes | Reaction key to remove |

**Responses:**

- `200`: Request executed successfully
  - Returns: `RemoveReactionOutput`
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

### Chats

#### `GET /v1/chats/search`

**Search chats**

Search chats by title/network or participants using Beeper Desktop's renderer algorithm.

**Parameters:**

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| `cursor` | query | `string` | No | Opaque pagination cursor; do not inspect. Use together with 'direction'. |
| `direction` | query | `string (after, before)` | No | Pagination direction used with 'cursor': 'before' fetches older results, 'after' fetches newer results. Defaults to 'before' when only 'cursor' is provided. |
| `inbox` | query | `string (primary, low-priority, archive)` | No | Filter by inbox type: "primary" (non-archived, non-low-priority), "low-priority", or "archive". If not specified, shows all chats. |
| `unreadOnly` | query | `boolean` | No | Set to true to only retrieve chats that have unread messages |
| `limit` | query | `integer` | No | Set the maximum number of chats to retrieve. Valid range: 1-200, default is 50 |
| `type` | query | `string (single, group, any)` | No | Specify the type of chats to retrieve: use "single" for direct messages, "group" for group chats, or "any" to get all types |
| `query` | query | `string` | No | Literal token search (non-semantic). Use single words users type (e.g., "dinner"). When multiple words provided, ALL must match. Case-insensitive. |
| `scope` | query | `string (titles, participants)` | No | Search scope: 'titles' matches title + network; 'participants' matches participant names. |
| `lastActivityBefore` | query | `string` | No | Provide an ISO datetime string to only retrieve chats with last activity before this time |
| `lastActivityAfter` | query | `string` | No | Provide an ISO datetime string to only retrieve chats with last activity after this time |
| `accountIDs` | query | `array` | No | Provide an array of account IDs to filter chats from specific messaging accounts only |
| `includeMuted` | query | `boolean` | No | Include chats marked as Muted by the user, which are usually less important. Default: true. Set to false if the user wants a more refined search. |

**Responses:**

- `200`: Request executed successfully
  - Returns: `SearchChatsOutput`
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

#### `GET /v1/chats`

**List chats**

List all chats sorted by last activity (most recent first). Combines all accounts into a single paginated list.

**Parameters:**

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| `cursor` | query | `string` | No | Opaque pagination cursor; do not inspect. Use together with 'direction'. |
| `direction` | query | `string (after, before)` | No | Pagination direction used with 'cursor': 'before' fetches older results, 'after' fetches newer results. Defaults to 'before' when only 'cursor' is provided. |
| `accountIDs` | query | `array` | No | Limit to specific account IDs. If omitted, fetches from all accounts. |

**Responses:**

- `200`: Request executed successfully
  - Returns: `ListChatsOutput`
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

#### `POST /v1/chats`

**Create or start a chat**

Create a single/group chat (mode='create') or start a direct chat from merged user data (mode='start').

**Request Body:** See `CreateChatInput` schema.

**Responses:**

- `200`: Request executed successfully
  - Returns: `CreateChatOutput`
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

#### `GET /v1/chats/{chatID}`

**Retrieve chat details**

Retrieve chat details including metadata, participants, and latest message

**Parameters:**

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| `chatID` | path | `string` | Yes | Unique identifier of the chat. |
| `maxParticipantCount` | query | `integer` | No | Maximum number of participants to return. Use -1 for all; otherwise 0–500. Defaults to all (-1). |

**Responses:**

- `200`: Request executed successfully
  - Returns: `Chat`
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

#### `POST /v1/chats/{chatID}/archive`

**Archive or unarchive a chat**

Archive or unarchive a chat. Set archived=true to move to archive, archived=false to move back to inbox

**Parameters:**

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| `chatID` | path | `string` | Yes | Unique identifier of the chat. |

**Request Body** (`application/json`):

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `archived` | `boolean` | No | True to archive, false to unarchive |

**Responses:**

- `204`: Request executed successfully
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

#### `POST /v1/chats/{chatID}/reminders`

**Create a chat reminder**

Set a reminder for a chat at a specific time

**Parameters:**

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| `chatID` | path | `string` | Yes | Unique identifier of the chat. |

**Request Body** (`application/json`):

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `reminder` | `object` | Yes | Reminder configuration |

**Responses:**

- `204`: Request executed successfully
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

#### `DELETE /v1/chats/{chatID}/reminders`

**Delete a chat reminder**

Clear an existing reminder from a chat

**Parameters:**

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| `chatID` | path | `string` | Yes | Unique identifier of the chat. |

**Responses:**

- `204`: Request executed successfully
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

### Contacts

#### `GET /v1/accounts/{accountID}/contacts`

**Search contacts**

Search contacts on a specific account using merged account contacts, network search, and exact identifier lookup.

**Parameters:**

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| `accountID` | path | `string` | Yes | Account ID this resource belongs to. |
| `query` | query | `string` | Yes | Text to search users by. Network-specific behavior. |

**Responses:**

- `200`: Request executed successfully
  - Returns: `SearchContactsOutput`
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

#### `GET /v1/accounts/{accountID}/contacts/list`

**List contacts**

List merged contacts for a specific account with cursor-based pagination.

**Parameters:**

| Name | In | Type | Required | Description |
|------|-----|------|----------|-------------|
| `accountID` | path | `string` | Yes | Account ID this resource belongs to. |
| `cursor` | query | `string` | No | Opaque pagination cursor; do not inspect. Use together with 'direction'. |
| `direction` | query | `string (after, before)` | No | Pagination direction used with 'cursor': 'before' fetches older results, 'after' fetches newer results. Defaults to 'before' when only 'cursor' is provided. |
| `limit` | query | `integer` | No | Maximum contacts to return per page. |
| `query` | query | `string` | No | Optional search query for blended contact lookup. |

**Responses:**

- `200`: Request executed successfully
  - Returns: `ListContactsOutput`
- `400`: 
- `401`: 
- `403`: 
- `404`: 
- `422`: 
- `429`: 
- `500`: 

---

# WebSocket API

**Status:** Experimental - may change between desktop releases.

## Connection

```
ws://localhost:23373/v1/ws
```

Use the same Bearer token as HTTP requests:
```
Authorization: Bearer <your_token>
```

## Subscription Model

Use `subscriptions.set` to fully replace current subscriptions.

- `chatIDs: ["*"]` - Subscribe to all chats
- `chatIDs: ["chatID1", "chatID2"]` - Subscribe to specific chats
- `chatIDs: []` - Pause events
- `"*"` cannot be mixed with specific chat IDs

### Subscribe to All Chats

```json
{
  "type": "subscriptions.set",
  "requestID": "r1",
  "chatIDs": ["*"]
}
```

### Subscribe to Specific Chats

```json
{
  "type": "subscriptions.set",
  "requestID": "r2",
  "chatIDs": ["<chatID1>", "<chatID2>"]
}
```

## Control Messages (Server to Client)

### `ready`

Sent when the WebSocket connection is established.

```json
{
  "type": "ready",
  "version": 1,
  "chatIDs": []
}
```

### `subscriptions.updated`

Confirms subscription changes.

```json
{
  "type": "subscriptions.updated",
  "requestID": "r2",
  "chatIDs": ["<chatID1>", "<chatID2>"]
}
```

### `error`

```json
{
  "type": "error",
  "requestID": "r2",
  "code": "INVALID_PAYLOAD",
  "message": "chatIDs cannot combine '*' with specific IDs"
}
```

## Domain Events (Server to Client)

All live domain events use this flat shape:

```json
{
  "type": "<event_name>",
  "seq": 42,
  "ts": 1739320000000,
  "chatID": "chat_a",
  "ids": ["m1", "m2"],
  "entries": [{ "id": "m1", "reactions": [] }]
}
```

### Event Fields

| Field | Type | Description |
|-------|------|-------------|
| `type` | `string` | Domain event name |
| `seq` | `integer` | Monotonic per-connection sequence number |
| `ts` | `integer` | Server timestamp in milliseconds |
| `chatID` | `string` | Canonical chat identifier |
| `ids` | `[string]` | Changed entity IDs |
| `entries` | `[object]` | Optional best-effort full payload objects (for `message.upserted`) |

### Event Names

| Event | Description |
|-------|-------------|
| `chat.upserted` | Chat created or updated |
| `chat.deleted` | Chat deleted (IDs only, no entries) |
| `message.upserted` | Message created or updated (includes full payload in entries) |
| `message.deleted` | Message deleted (IDs only, no entries) |

### Notes

- Both `upsert` and `update` sync mutations are delivered as `<resource>.upserted` events
- `message.upserted` entries are hydrated from the local message endpoint (includes attachments)
- If a message is not yet retrievable, the event is skipped
- `message.deleted` and `chat.deleted` are emitted as IDs-only payloads (no `entries`)
