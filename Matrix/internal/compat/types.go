package compat

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
type ChatType string

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
	LastActivity           time.Time    `json:"lastActivity" format:"date-time"`
	LastReadMessageSortKey string       `json:"lastReadMessageSortKey"`
	// Chat-level image (Matrix m.room.avatar). Used by clients to show a real
	// group photo instead of a participant collage. Empty when the room has
	// no explicit avatar.
	ImgURL string `json:"imgURL,omitempty"`
	// List chats includes an optional preview object.
	Preview *Message `json:"preview,omitempty"`
	// Marked unread is separate from unreadCount.
	IsMarkedUnread bool `json:"isMarkedUnread"`
}

type ListChatsOutput struct {
	Items   []Chat `json:"items"`
	HasMore bool   `json:"hasMore"`
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

type EditMessageInput struct {
	Text string `json:"text"`
}

type ReactionInput struct {
	ReactionKey string `json:"reactionKey"`
}

type ActionSuccessOutput struct {
	Success bool `json:"success"`
}
