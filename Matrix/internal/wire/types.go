// Package wire defines the JSON shapes the core exchanges with the Swift app.
// Field names and tags are the app's protocol; change them only together with
// the Swift models that decode them.
package wire

import (
	"time"
)

type User struct {
	ID       string `json:"id"`
	FullName string `json:"fullName"`
	ImgURL   string `json:"imgURL"`
	IsSelf   bool   `json:"isSelf"`
	Username string `json:"username"`
}

// Account is one login: the Matrix account itself, or one network login on a
// bridge. A bridge with several logins, such as two Slack workspaces, has one
// account for each.
type Account struct {
	// AccountID is unique per login. Chats carry it to name their login.
	AccountID string `json:"accountID"`
	// BridgeID names the bridge, such as "slackgo"; its logins share it.
	BridgeID string `json:"bridgeID"`
	User     User   `json:"user"`
	Network  string `json:"network"`
	// LoginName is how the bridge names the login, such as a phone number.
	LoginName string `json:"loginName,omitempty"`
	// NetworkImgURL is the network's logo as its bridge publishes it, an
	// mxc:// URI. Empty when the bridge publishes none.
	NetworkImgURL string `json:"networkImgURL,omitempty"`
	// Workspace is the team the login is in, on networks like Slack where
	// each login is one workspace.
	Workspace    *Workspace          `json:"workspace,omitempty"`
	Capabilities AccountCapabilities `json:"capabilities"`
}

// Workspace is a Slack-style team one login belongs to.
type Workspace struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	ImgURL string `json:"imgURL,omitempty"`
}

type AccountCapabilities struct {
	UnlimitedMessageEdits bool `json:"unlimitedMessageEdits"`
	// Threads means replies go into threads, as on Slack, which has no
	// quoted replies.
	Threads bool `json:"threads"`
}

type SessionOutput struct {
	User     User      `json:"user"`
	Accounts []Account `json:"accounts"`
}

type Participants struct {
	HasMore bool   `json:"hasMore"`
	Items   []User `json:"items"`
	Total   int64  `json:"total"`
}

type Attachment struct {
	Type      AttachmentType `json:"type"`
	ID        string         `json:"id"`
	Duration  float64        `json:"duration"`
	FileName  string         `json:"fileName"`
	FileSize  float64        `json:"fileSize"`
	IsGif     bool           `json:"isGif"`
	MimeType  string         `json:"mimeType"`
	PosterImg string         `json:"posterImg"`
	Size      AttachmentSize `json:"size"`
	SrcURL    string         `json:"srcURL"`
}

type AttachmentSize struct {
	Height float64 `json:"height"`
	Width  float64 `json:"width"`
}

type Reaction struct {
	ID            string `json:"id"`
	ParticipantID string `json:"participantID"`
	ReactionKey   string `json:"reactionKey"`
	Participant   *User  `json:"participant,omitempty"`
}

type AttachmentType string

const (
	AttachmentTypeUnknown AttachmentType = "unknown"
	AttachmentTypeImage   AttachmentType = "img"
	AttachmentTypeVideo   AttachmentType = "video"
	AttachmentTypeAudio   AttachmentType = "audio"
	// AttachmentTypeReel is an Instagram Reel placeholder the app can resolve
	// into the actual video with resolve-media.
	AttachmentTypeReel AttachmentType = "reel"
)

type ChatType string

const (
	ChatTypeSingle ChatType = "single"
	ChatTypeGroup  ChatType = "group"
)

// Message is one timeline message as the app renders it. Redacted Matrix
// events can retain their original content in the local database, so the app
// renders that content with deleted styling instead of a generic tombstone.
type Message struct {
	TransactionID   string       `json:"transactionID,omitempty"`
	ID              string       `json:"id"`
	ChatID          string       `json:"chatID"`
	SenderID        string       `json:"senderID"`
	SortKey         string       `json:"sortKey"`
	Timestamp       time.Time    `json:"timestamp"`
	Attachments     []Attachment `json:"attachments"`
	IsSender        bool         `json:"isSender"`
	IsUnread        bool         `json:"isUnread"`
	IsDeleted       bool         `json:"isDeleted,omitempty"`
	LinkedMessageID string       `json:"linkedMessageID"`
	Reactions       []Reaction   `json:"reactions"`
	SenderName      string       `json:"senderName"`
	// Sender is the sender's profile from their member event. A chat's
	// participants are only a sample, so it is how a group's timeline draws
	// and opens every sender.
	Sender *User `json:"sender,omitempty"`
	// A visible personal mention, excluding reply fallback notifications.
	IsPersonalMention bool   `json:"isPersonalMention,omitempty"`
	Text              string `json:"text"`
	// FormattedText is display Markdown converted from the HTML body, with
	// links, lists, headings, code and Matrix user links preserved.
	// Text remains the plain body for previews, copying and editing.
	FormattedText string           `json:"formattedText,omitempty"`
	Mentions      *MessageMentions `json:"mentions,omitempty"`
	// ThreadRootID is the message whose thread this one replies in. Thread
	// replies stay out of the main timeline unless IsThreadBroadcast is set.
	ThreadRootID string `json:"threadRootID,omitempty"`
	// IsThreadBroadcast marks a thread reply also sent to the chat, like
	// Slack's "Also send to channel".
	IsThreadBroadcast bool `json:"isThreadBroadcast,omitempty"`
	// IsForwarded marks a message a bridge labeled as forwarded; the label
	// itself is removed from the text.
	IsForwarded bool `json:"isForwarded,omitempty"`
	// IsNotice marks an m.notice, which bridges use for their own status
	// lines rather than anything the sender wrote.
	IsNotice bool `json:"isNotice,omitempty"`
	// Thread summarizes the replies to this message; nil when it has none.
	Thread *ThreadSummary `json:"thread,omitempty"`
	// DeliveryStatus is the bridge's latest report on an outgoing message;
	// empty when no bridge reported on it.
	DeliveryStatus DeliveryStatus `json:"deliveryStatus,omitempty"`
	// DeliveryError is the bridge's explanation of a failed delivery, when
	// it gave one.
	DeliveryError string `json:"deliveryError,omitempty"`
	// LinkPreview is the first usable preview a bridge sent with the
	// message; nil when it sent none.
	LinkPreview *LinkPreview `json:"linkPreview,omitempty"`
	// LinkPreviewURL is the first link worth previewing when no bridge
	// preview came with the message. The app fetches its preview with
	// get-link-preview only when the message is shown.
	LinkPreviewURL string `json:"linkPreviewURL,omitempty"`
}

// DeliveryStatus is how far an outgoing message got past the homeserver.
type DeliveryStatus string

const (
	// DeliveryStatusSent means the bridge handed it to the network.
	DeliveryStatusSent DeliveryStatus = "sent"
	// DeliveryStatusDelivered means the recipient's device confirmed it.
	DeliveryStatusDelivered DeliveryStatus = "delivered"
	// DeliveryStatusFailed means the network didn't take it.
	DeliveryStatusFailed DeliveryStatus = "failed"
)

// ThreadSummary is what a thread root shows under its bubble.
type ThreadSummary struct {
	ReplyCount int `json:"replyCount"`
	// The most recent repliers first, at most a few.
	Participants []User `json:"participants"`
	// HasUnread marks a reply that notified you since you last saw the thread.
	HasUnread bool `json:"hasUnread,omitempty"`
}

// MessageMentions preserves intentional notifications separately from visible
// user links. A link can exist without notifying its target, and vice versa.
type MessageMentions struct {
	UserIDs []string `json:"userIDs"`
	Room    bool     `json:"room"`
}

// ListMentionsOutput is one bounded page after the captured read position.
// After stays fixed until the reader visits a mention, even if receipts change.
type ListMentionsOutput struct {
	Items   []Message `json:"items"`
	After   string    `json:"after"`
	HasMore bool      `json:"hasMore"`
}

type Chat struct {
	ID                     string       `json:"id"`
	AccountID              string       `json:"accountID"`
	Participants           Participants `json:"participants"`
	Title                  string       `json:"title"`
	Type                   ChatType     `json:"type"`
	UnreadCount            int64        `json:"unreadCount"`
	IsArchived             bool         `json:"isArchived"`
	IsMuted                bool         `json:"isMuted"`
	IsPinned               bool         `json:"isPinned"`
	PinOrder               *float64     `json:"pinOrder,omitempty"`
	LastActivity           time.Time    `json:"lastActivity"`
	LastReadMessageSortKey string       `json:"lastReadMessageSortKey"`
	// The room's own m.room.avatar, so the app can show a real group photo
	// instead of a participant collage. Empty when the room has none.
	ImgURL string `json:"imgURL,omitempty"`
	// The newest message usable as a sidebar preview, if any.
	Preview *Message `json:"preview,omitempty"`
	// Marked unread is separate from unreadCount.
	IsMarkedUnread bool `json:"isMarkedUnread"`
	// Whether an unread message highlights the user, which is how push rules
	// mark a mention of them.
	HasUnreadMention bool `json:"hasUnreadMention"`
}

type ListChatsOutput struct {
	Items   []Chat `json:"items"`
	HasMore bool   `json:"hasMore"`
	Pinned  []Chat `json:"pinned,omitempty"`
}

// ReadReceipt is how far another participant has read a chat.
type ReadReceipt struct {
	UserID string `json:"userID"`
	// Participant is the reader's profile from their member event, as a
	// message's sender and a reaction's participant are.
	Participant User `json:"participant"`
	// SortKey is the furthest message they have read.
	SortKey string `json:"sortKey"`
}

type ListMessagesOutput struct {
	Items        []Message `json:"items"`
	HasMore      bool      `json:"hasMore"`
	OldestCursor string    `json:"oldestCursor,omitempty"`
	// ReadReceipts holds how far each other participant has read. Outgoing
	// messages with a sortKey up to a receipt's have been seen by that person.
	ReadReceipts []ReadReceipt `json:"readReceipts,omitempty"`
	// HasServerHistory is false once the homeserver has returned the start of
	// the room; until then older history may exist beyond the local timeline.
	HasServerHistory bool `json:"hasServerHistory"`
	// NewestCursor and HasMoreNewer describe the newer side of a page read
	// around a message or after a cursor, which may stop short of the newest
	// message. Plain pages are always the newest and leave them unset.
	NewestCursor string `json:"newestCursor,omitempty"`
	HasMoreNewer bool   `json:"hasMoreNewer,omitempty"`
}

// GetMessagesOutput holds the requested messages the local database has;
// IDs it doesn't store are absent.
type GetMessagesOutput struct {
	Items []Message `json:"items"`
}

// ListThreadOutput is one thread: its root and every local reply, oldest first.
type ListThreadOutput struct {
	Root  *Message  `json:"root,omitempty"`
	Items []Message `json:"items"`
}

type LoadServerHistoryOutput struct {
	// HasMore is false once the homeserver has returned the start of the room.
	HasMore bool `json:"hasMore"`
}

type SendMessageOutput struct {
	ChatID           string `json:"chatID"`
	PendingMessageID string `json:"pendingMessageID"`
	// CaptionRejected reports that the chat's network takes no media
	// captions, so the media went without its text. The sender sends the
	// text as its own message after the remaining media.
	CaptionRejected bool `json:"captionRejected,omitempty"`
}

type SendMessageInput struct {
	Text             string                 `json:"text"`
	ReplyToMessageID string                 `json:"replyToMessageID"`
	Attachment       MessageAttachmentInput `json:"attachment"`
	Mentions         []ComposerMention      `json:"mentions"`
	// ThreadRootID sends the message as a reply in that message's thread.
	ThreadRootID string `json:"threadRootID"`
	// AlsoSendToChat shows a thread reply in the main timeline too.
	AlsoSendToChat bool `json:"alsoSendToChat"`
	// AfterPendingMessageID holds this message until that earlier one in the
	// same send has reached the server, so the network receives them in order.
	AfterPendingMessageID string `json:"afterPendingMessageID,omitempty"`
}

// ComposerMention identifies an explicitly selected span, in UTF-16 units.
type ComposerMention struct {
	UserID   string `json:"userID"`
	Location int    `json:"location"`
	Length   int    `json:"length"`
}

type MessageAttachmentInput struct {
	UploadID string         `json:"uploadID"`
	FileName string         `json:"fileName"`
	MimeType string         `json:"mimeType"`
	Size     AttachmentSize `json:"size"`
}

// SearchMessagesOutput is one page of message search results across chats,
// newest first, with the chats they're in.
type SearchMessagesOutput struct {
	Items []Message `json:"items"`
	// Chats holds each result's chat once, without preview or read state.
	Chats   []Chat `json:"chats"`
	HasMore bool   `json:"hasMore"`
	// Cursor continues after this page; empty when it found nothing.
	Cursor string `json:"cursor,omitempty"`
}

// ChatInfoOutput is what a chat's info screen shows below its header.
type ChatInfoOutput struct {
	// Counts of the locally stored messages in each browsable kind.
	MediaCount int `json:"mediaCount"`
	FileCount  int `json:"fileCount"`
	LinkCount  int `json:"linkCount"`
	// CanDeleteChat is set when the room's bridge deletes the chat on its
	// network; otherwise deleting only leaves the room.
	CanDeleteChat bool `json:"canDeleteChat"`
}

// ChatMessagePageOutput is one page of a chat's media, files or links,
// newest first.
type ChatMessagePageOutput struct {
	Items   []Message `json:"items"`
	HasMore bool      `json:"hasMore"`
	// Cursor continues after this page's oldest row; empty when the page
	// is empty.
	Cursor string `json:"cursor,omitempty"`
	// HasServerHistory is true while older history can still be fetched
	// into the local store, where later pages can find it.
	HasServerHistory bool `json:"hasServerHistory"`
}

type ActionSuccessOutput struct {
	Success bool `json:"success"`
}

// Success is the reply for commands that only report completion.
var Success = ActionSuccessOutput{Success: true}
