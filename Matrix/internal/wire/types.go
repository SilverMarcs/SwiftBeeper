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

type Account struct {
	AccountID    string              `json:"accountID"`
	User         User                `json:"user"`
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
	Text            string       `json:"text"`
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
}

type ListChatsOutput struct {
	Items   []Chat `json:"items"`
	HasMore bool   `json:"hasMore"`
	Pinned  []Chat `json:"pinned,omitempty"`
}

type ListMessagesOutput struct {
	Items        []Message `json:"items"`
	HasMore      bool      `json:"hasMore"`
	OldestCursor string    `json:"oldestCursor,omitempty"`
	// LastReadByOtherSortKey is the sortKey of the furthest message that at least
	// one other participant has read. Outgoing messages with sortKey <= this value
	// have been seen by the other side. Empty string if no read receipt exists.
	LastReadByOtherSortKey string `json:"lastReadByOtherSortKey,omitempty"`
}

type SendMessageOutput struct {
	ChatID           string `json:"chatID"`
	PendingMessageID string `json:"pendingMessageID"`
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
	Size     AttachmentSize `json:"size"`
}

type ActionSuccessOutput struct {
	Success bool `json:"success"`
}

// Success is the reply for commands that only report completion.
var Success = ActionSuccessOutput{Success: true}
