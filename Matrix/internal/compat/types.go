package compat

import (
	"time"

	beeperdesktopapi "github.com/beeper/desktop-api-go"
	"github.com/beeper/desktop-api-go/shared"
)

type User = shared.User

type Account struct {
	AccountID    string              `json:"accountID"`
	User         User                `json:"user"`
	NetworkID    string              `json:"networkID"`
	Network      string              `json:"network"`
	Capabilities AccountCapabilities `json:"capabilities"`
}

type AccountCapabilities struct {
	UnlimitedMessageEdits bool `json:"unlimitedMessageEdits"`
}

type SessionOutput struct {
	User     User      `json:"user"`
	Accounts []Account `json:"accounts"`
}

type Participants = beeperdesktopapi.ChatParticipants
type Attachment = shared.Attachment
type AttachmentType = shared.AttachmentType
type AttachmentSize = shared.AttachmentSize
type Reaction = shared.Reaction
type MessageType = shared.MessageType
type ChatType = beeperdesktopapi.ChatType

// Message extends the desktop API-compatible message shape with deletion
// state. Redacted Matrix events can retain their original content in the local
// database, so clients can render that content with deleted styling instead of
// replacing it with a generic tombstone.
type Message struct {
	ID              string       `json:"id"`
	AccountID       string       `json:"accountID"`
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
	Text            string       `json:"text"`
	Type            MessageType  `json:"type"`
}

type Chat struct {
	beeperdesktopapi.Chat
	// Extension for current renderer expectations.
	Network string `json:"network,omitempty"`
	// Chat-level image (Matrix m.room.avatar). Used by clients to show a real
	// group photo instead of a participant collage. Empty when the room has
	// no explicit avatar.
	ImgURL string `json:"imgURL,omitempty"`
	// List chats includes an optional preview object.
	Preview *Message `json:"preview,omitempty"`
	// Desktop-side consumers treat marked unread separately from unreadCount.
	IsMarkedUnread bool `json:"isMarkedUnread"`
	// Extra metadata consumed by Desktop-side inbox/archive logic.
	Extra *ChatExtra `json:"extra,omitempty"`
	// Snooze metadata used by Desktop-side scheduling views.
	Snooze *ChatSnooze `json:"snooze,omitempty"`
}

type ChatExtra struct {
	MarkedUnreadUpdatedAt int64 `json:"markedUnreadUpdatedAt,omitempty"`
}

type ChatSnooze struct {
	SnoozeUntilMS *int64 `json:"snoozeUntilMs,omitempty"`
	UserSnoozedAt *int64 `json:"userSnoozedAt,omitempty"`
}

type ListChatsOutput struct {
	Items        []Chat  `json:"items"`
	HasMore      bool    `json:"hasMore"`
	OldestCursor *string `json:"oldestCursor"`
	NewestCursor *string `json:"newestCursor"`
}

type SearchChatsOutput = ListChatsOutput

type ListMessagesOutput struct {
	Items        []Message `json:"items"`
	HasMore      bool      `json:"hasMore"`
	OldestCursor string    `json:"oldestCursor,omitempty"`
	Preview      *Message  `json:"preview,omitempty"`
	// LastReadByOtherSortKey is the sortKey of the furthest message that at least
	// one other participant has read. Outgoing messages with sortKey <= this value
	// have been seen by the other side. Empty string if no read receipt exists.
	LastReadByOtherSortKey string `json:"lastReadByOtherSortKey,omitempty"`
}

type SendMessageOutput = beeperdesktopapi.MessageSendResponse
type EditMessageOutput = beeperdesktopapi.MessageUpdateResponse

type AddReactionOutput = beeperdesktopapi.ChatMessageReactionAddResponse

type RemoveReactionOutput = beeperdesktopapi.ChatMessageReactionDeleteResponse

type SendMessageInput = beeperdesktopapi.MessageSendParams
type MessageAttachmentInput = beeperdesktopapi.MessageSendParamsAttachment
type EditMessageInput = beeperdesktopapi.MessageUpdateParams

type AddReactionInput struct {
	ReactionKey   string `json:"reactionKey"`
	TransactionID string `json:"transactionID,omitempty"`
}

type RemoveReactionInput struct {
	ReactionKey string `json:"reactionKey"`
}

type ActionSuccessOutput struct {
	Success bool `json:"success"`
}
