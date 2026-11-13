// Package notifications decrypts one notified event without opening a database,
// starting sync, or modifying the app's Olm account.
package notifications

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/crypto/backup"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

// Credentials are the parts of the app's session the extension needs.
type Credentials struct {
	Homeserver  string      `json:"homeserver"`
	UserID      id.UserID   `json:"userID"`
	DeviceID    id.DeviceID `json:"deviceID"`
	AccessToken string      `json:"accessToken"`
	BackupKey   string      `json:"backupKey"`
}

type Request struct {
	Credentials
	RoomID  id.RoomID  `json:"roomID"`
	EventID id.EventID `json:"eventID"`
	// CacheDirectory holds names and avatars from earlier pushes; optional.
	CacheDirectory string `json:"cacheDirectory"`
}

type Preview struct {
	Title         string        `json:"title"`
	Body          string        `json:"body"`
	SenderID      string        `json:"senderID"`
	SenderName    string        `json:"senderName"`
	IsGroup       bool          `json:"isGroup"`
	Avatar        []byte        `json:"avatar,omitempty"`
	Recipients    []Participant `json:"recipients,omitempty"`
	TargetEventID id.EventID    `json:"targetEventID,omitempty"`
	MentionsMe    bool          `json:"mentionsMe"`
	// ThreadRootID is the thread a reply belongs to, which opening the
	// notification shows over its chat.
	ThreadRootID id.EventID `json:"threadRootID,omitempty"`
}

type Participant struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// One client per extension process, so a burst of pushes shares its connection
// to the homeserver instead of a fresh TLS handshake per push.
var httpClient = &http.Client{Timeout: 8 * time.Second}

// When the last push started, in Unix nanoseconds. iOS freezes the extension
// between pushes, so a connection idle longer than idleConnectionLimit is
// likely dead and requests on it would hang until they time out.
var lastFetch atomic.Int64

const idleConnectionLimit = 10 * time.Second

// Fetch builds the preview for one notified event.
func Fetch(ctx context.Context, req Request) (*Preview, error) {
	if req.RoomID == "" || req.EventID == "" || req.AccessToken == "" || !strings.HasPrefix(req.Homeserver, "https://") {
		return nil, errors.New("invalid notification context")
	}
	cli, err := mautrix.NewClient(req.Homeserver, req.UserID, req.AccessToken)
	if err != nil {
		return nil, err
	}
	if now := time.Now(); now.Sub(time.Unix(0, lastFetch.Swap(now.UnixNano()))) > idleConnectionLimit {
		httpClient.CloseIdleConnections()
	}
	cli.Client = httpClient
	ctx = mautrix.WithMaxRetries(ctx, 0)
	store := newCache(req.CacheDirectory, string(req.UserID))

	// Requests that don't depend on the event run while it downloads. Room
	// metadata shares one short budget, counted once the event has arrived so
	// that connecting doesn't use it up, and never reads the member list.
	metadataCtx, cancel := context.WithCancel(ctx)
	defer cancel()
	var roomName event.RoomNameEventContent
	var roomAvatar event.RoomAvatarEventContent
	var ownMembership event.MemberEventContent
	var roomMetadata sync.WaitGroup
	roomMetadata.Add(3)
	go func() {
		defer roomMetadata.Done()
		err := cli.StateEvent(metadataCtx, req.RoomID, event.StateRoomName, "", &roomName)
		store.remember("room-names", req.RoomID.String(), &roomName, err)
	}()
	go func() {
		defer roomMetadata.Done()
		err := cli.StateEvent(metadataCtx, req.RoomID, event.StateRoomAvatar, "", &roomAvatar)
		store.remember("room-avatars", req.RoomID.String(), &roomAvatar, err)
	}()
	go func() {
		defer roomMetadata.Done()
		err := cli.StateEvent(metadataCtx, req.RoomID, event.StateMember, req.UserID.String(), &ownMembership)
		store.remember("room-memberships", req.RoomID.String(), &ownMembership, err)
	}()
	// Most chats are encrypted, so look up the key backup alongside too.
	var backupVersion *mautrix.RespRoomKeysVersion[backup.MegolmAuthData]
	var backupErr error
	var backupLookup sync.WaitGroup
	backupLookup.Add(1)
	go func() {
		defer backupLookup.Done()
		backupVersion, backupErr = cli.GetKeyBackupLatestVersion(ctx)
	}()

	evt, err := cli.GetEvent(ctx, req.RoomID, req.EventID)
	if err != nil {
		return nil, err
	}
	if evt.ID != req.EventID || (evt.RoomID != "" && evt.RoomID != req.RoomID) {
		return nil, errors.New("event mismatch")
	}
	time.AfterFunc(2*time.Second, cancel)
	sender := evt.Sender.String()
	var senderAvatar id.ContentURIString
	// The sender's profile gets its own budget, since the room reads started earlier.
	profileCtx, cancelProfile := context.WithTimeout(ctx, 2*time.Second)
	defer cancelProfile()
	var senderProfile sync.WaitGroup
	senderProfile.Add(1)
	go func() {
		defer senderProfile.Done()
		var profile mautrix.RespUserProfile
		fetched, err := cli.GetProfile(profileCtx, evt.Sender)
		if err == nil {
			profile = *fetched
		}
		store.remember("profiles", evt.Sender.String(), &profile, err)
		if name := strings.TrimSpace(profile.DisplayName); name != "" {
			sender = name
		}
		if !profile.AvatarURL.IsEmpty() {
			senderAvatar = id.ContentURIString(profile.AvatarURL.String())
		}
	}()

	content := evt.Content.VeryRaw
	typ := evt.Type.Type
	if typ == event.EventEncrypted.Type {
		typ, content, err = decryptWithBackup(ctx, cli, req, content, func() (*mautrix.RespRoomKeysVersion[backup.MegolmAuthData], error) {
			backupLookup.Wait()
			return backupVersion, backupErr
		})
		if err != nil {
			return nil, err
		}
	}
	body, targetEventID, err := notificationBody(ctx, cli, req, evt.Sender, typ, content)
	if err != nil {
		return nil, err
	}

	roomMetadata.Wait()
	senderProfile.Wait()
	title := sender
	name := strings.TrimSpace(roomName.Name)
	isGroup := name != "" && name != sender && !ownMembership.IsDirect
	var recipients []Participant
	if name == "" && !ownMembership.IsDirect {
		// Bridges can omit m.room.name for group DMs. Additional people,
		// excluding the service bot, distinguish them from one-to-one chats.
		recipients = fetchRecipients(ctx, cli, store, req.RoomID, req.UserID, evt.Sender)
		if len(recipients) > 0 {
			isGroup = true
			names := []string{sender}
			for _, recipient := range recipients {
				names = append(names, recipient.Name)
			}
			name = strings.Join(names, ", ")
		}
	}
	if name != "" {
		title = name
	}
	avatarURL := senderAvatar
	if isGroup {
		// Never label a sender's portrait as the group's picture.
		avatarURL = roomAvatar.URL
	} else if roomAvatar.URL != "" {
		// A direct room can have a contact-specific photo.
		avatarURL = roomAvatar.URL
	}
	preview := &Preview{Title: truncate(title, 120), Body: truncate(body, 500),
		SenderID: evt.Sender.String(), SenderName: truncate(sender, 120), IsGroup: isGroup,
		Recipients: recipients, TargetEventID: targetEventID, MentionsMe: mentionsUser(content, req.UserID),
		ThreadRootID: threadRoot(evt.Content.VeryRaw)}
	var extras sync.WaitGroup
	extras.Add(1)
	go func() {
		defer extras.Done()
		preview.Avatar = fetchAvatar(ctx, cli, store, avatarURL)
	}()
	if isGroup && recipients == nil {
		extras.Add(1)
		go func() {
			defer extras.Done()
			preview.Recipients = fetchRecipients(ctx, cli, store, req.RoomID, req.UserID, evt.Sender)
		}()
	}
	extras.Wait()
	return preview, nil
}

// threadRoot returns the thread a reply belongs to. Encryption leaves the
// relation readable, so this is the event's outer content.
func threadRoot(content json.RawMessage) id.EventID {
	var parsed struct {
		RelatesTo *event.RelatesTo `json:"m.relates_to"`
	}
	if json.Unmarshal(content, &parsed) != nil || parsed.RelatesTo == nil || parsed.RelatesTo.Type != event.RelThread {
		return ""
	}
	return parsed.RelatesTo.EventID
}

// Use recipient metadata, never a name match or the generic highlight tweak
// (which can also mean a reply or keyword). A mention is part of its message.
func mentionsUser(content json.RawMessage, userID id.UserID) bool {
	var message event.MessageEventContent
	if userID == "" || json.Unmarshal(content, &message) != nil {
		return false
	}
	if message.NewContent != nil {
		message = *message.NewContent
	}
	return message.Mentions != nil && message.Mentions.Has(userID)
}

// notificationBody describes a message, or a reaction to one of the user's
// messages, in which case it also returns the reacted-to event.
func notificationBody(ctx context.Context, cli *mautrix.Client, req Request, sender id.UserID, typ string, content json.RawMessage) (string, id.EventID, error) {
	if typ == event.EventReaction.Type {
		var reaction event.ReactionEventContent
		if err := json.Unmarshal(content, &reaction); err != nil {
			return "", "", err
		}
		if sender == req.UserID || reaction.RelatesTo.Type != event.RelAnnotation ||
			reaction.RelatesTo.EventID == "" || strings.TrimSpace(reaction.RelatesTo.Key) == "" {
			return "", "", errors.New("invalid reaction notification")
		}
		target, err := cli.GetEvent(ctx, req.RoomID, reaction.RelatesTo.EventID)
		if err != nil {
			return "", "", err
		}
		if target.ID != reaction.RelatesTo.EventID || target.Sender != req.UserID ||
			(target.RoomID != "" && target.RoomID != req.RoomID) ||
			(target.Type != event.EventMessage && target.Type != event.EventEncrypted && target.Type != event.EventSticker) {
			return "", "", errors.New("reaction is not to your message")
		}
		return "Reacted " + reaction.RelatesTo.Key + " to your message", target.ID, nil
	}
	if typ != event.EventMessage.Type && typ != event.EventSticker.Type {
		return "", "", errors.New("not a message")
	}
	var message event.MessageEventContent
	if err := json.Unmarshal(content, &message); err != nil {
		return "", "", err
	}
	if message.NewContent != nil {
		message = *message.NewContent
	}
	message.RemoveReplyFallback()
	body := messageSummary(typ, &message)
	if strings.TrimSpace(body) == "" {
		body = "New message"
	}
	return body, "", nil
}

// messageSummary is a message's notification text. Media leads with an emoji
// for its kind, then the authored caption, or the kind's name without one.
// Matrix media fills Body with the filename when there's no caption, so the
// caption comes from GetCaption rather than Body.
func messageSummary(typ string, message *event.MessageEventContent) string {
	if typ == event.EventSticker.Type {
		// A sticker's body is its alt text, which bridges set to the emoji
		// it stands for.
		if alt := strings.TrimSpace(message.Body); isEmojiOnly(alt) {
			return alt + " Sticker"
		}
		return "Sticker"
	}
	caption := plainText(strings.TrimSpace(message.GetCaption()))
	withCaption := func(emoji, name string) string {
		if caption == "" {
			return emoji + " " + name
		}
		return emoji + " " + caption
	}
	switch message.MsgType {
	case event.MsgImage:
		if message.Info != nil && (message.Info.MauGIF || message.Info.MimeType == "image/gif") {
			return withCaption("🎞️", "GIF")
		}
		return withCaption("📷", "Photo")
	case event.MsgVideo:
		if message.Info != nil && message.Info.MauGIF {
			return withCaption("🎞️", "GIF")
		}
		return withCaption("🎥", "Video")
	case event.MsgAudio:
		if message.MSC3245Voice != nil {
			return withCaption("🎤", "Voice message")
		}
		return withCaption("🎵", "Audio")
	case event.MsgFile:
		name := strings.TrimSpace(message.GetFileName())
		if name == "" {
			name = "File"
		}
		return withCaption("📎", name)
	case event.MsgLocation:
		return "📍 Location"
	}
	// Formatted messages carry their Markdown source as the plain body.
	return plainText(message.Body)
}

// isEmojiOnly reports whether s is one or more emoji, with their joiners,
// variation selectors and skin tone modifiers.
func isEmojiOnly(s string) bool {
	if s == "" {
		return false
	}
	hasEmoji := false
	for _, r := range s {
		switch {
		case r == 0x200D || r == 0xFE0F || (r >= 0x1F3FB && r <= 0x1F3FF) || (r >= 0xE0020 && r <= 0xE007F):
			// Zero-width joiner, emoji presentation, skin tones, flag tags.
		case (r >= 0x1F000 && r <= 0x1FAFF) || (r >= 0x2600 && r <= 0x27BF) || (r >= 0x2B00 && r <= 0x2BFF) ||
			(r >= 0x2190 && r <= 0x21FF) || (r >= 0x2300 && r <= 0x23FF) || r == 0x00A9 || r == 0x00AE ||
			r == 0x203C || r == 0x2049 || r == 0x2122 || r == 0x2139 || r == 0x3030 || r == 0x303D:
			hasEmoji = true
		default:
			return false
		}
	}
	return hasEmoji
}

func truncate(s string, limit int) string {
	runes := []rune(s)
	if len(runes) > limit {
		return string(runes[:limit]) + "…"
	}
	return s
}
