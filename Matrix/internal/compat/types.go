package compat

import (
	"time"
)

type User struct {
	ID            string `json:"id"`
	CannotMessage bool   `json:"cannotMessage"`
	Email         string `json:"email"`
	FullName      string `json:"fullName"`
	ImgURL        string `json:"imgURL"`
	IsSelf        bool   `json:"isSelf"`
	PhoneNumber   string `json:"phoneNumber"`
	Username      string `json:"username"`
}

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

type Participants struct {
	HasMore bool   `json:"hasMore"`
	Items   []User `json:"items"`
	Total   int64  `json:"total"`
}

type Attachment struct {
	Type        AttachmentType `json:"type"`
	ID          string         `json:"id"`
	Duration    float64        `json:"duration"`
	FileName    string         `json:"fileName"`
	FileSize    float64        `json:"fileSize"`
	IsGif       bool           `json:"isGif"`
	IsSticker   bool           `json:"isSticker"`
	IsVoiceNote bool           `json:"isVoiceNote"`
	MimeType    string         `json:"mimeType"`
	PosterImg   string         `json:"posterImg"`
	Size        AttachmentSize `json:"size"`
	SrcURL      string         `json:"srcURL"`
}

type AttachmentSize struct {
	Height float64 `json:"height"`
	Width  float64 `json:"width"`
}

type Reaction struct {
	ID            string `json:"id"`
	ParticipantID string `json:"participantID"`
	ReactionKey   string `json:"reactionKey"`
	Emoji         bool   `json:"emoji"`
	ImgURL        string `json:"imgURL"`
}

type AttachmentType string
type MessageType string
type ChatType string

// Message extends the desktop API-compatible message shape with deletion
// state. Redacted Matrix events can retain their original content in the local
// database, so clients can render that content with deleted styling instead of
// replacing it with a generic tombstone.
type Message struct {
	TransactionID   string       `json:"transactionID,omitempty"`
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
	ID                     string       `json:"id"`
	AccountID              string       `json:"accountID"`
	Participants           Participants `json:"participants"`
	Title                  string       `json:"title"`
	Type                   ChatType     `json:"type"`
	UnreadCount            int64        `json:"unreadCount"`
	IsArchived             bool         `json:"isArchived"`
	IsMuted                bool         `json:"isMuted"`
	IsPinned               bool         `json:"isPinned"`
	LastActivity           time.Time    `json:"lastActivity" format:"date-time"`
	LastReadMessageSortKey string       `json:"lastReadMessageSortKey"`
	LocalChatID            string       `json:"localChatID"`
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

type SendMessageOutput struct {
	ChatID           string `json:"chatID"`
	PendingMessageID string `json:"pendingMessageID"`
}

type EditMessageOutput struct {
	ChatID    string `json:"chatID"`
	MessageID string `json:"messageID"`
	Success   bool   `json:"success"`
}

type AddReactionOutput struct {
	ChatID        string `json:"chatID"`
	MessageID     string `json:"messageID"`
	ReactionKey   string `json:"reactionKey"`
	Success       bool   `json:"success"`
	TransactionID string `json:"transactionID"`
}

type RemoveReactionOutput struct {
	ChatID      string `json:"chatID"`
	MessageID   string `json:"messageID"`
	ReactionKey string `json:"reactionKey"`
	Success     bool   `json:"success"`
}

type SendMessageInput struct {
	Text             string                 `json:"text"`
	ReplyToMessageID string                 `json:"replyToMessageID"`
	Attachment       MessageAttachmentInput `json:"attachment"`
}

type MessageAttachmentInput struct {
	UploadID string         `json:"uploadID"`
	FileName string         `json:"fileName"`
	MimeType string         `json:"mimeType"`
	Duration float64        `json:"duration"`
	Size     AttachmentSize `json:"size"`
	Type     string         `json:"type"`
}

type EditMessageInput struct {
	Text string `json:"text"`
}

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
