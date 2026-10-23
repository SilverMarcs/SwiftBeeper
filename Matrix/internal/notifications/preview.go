// Package notifications decrypts one notified event without opening a database,
// starting sync, or modifying the app's Olm account.
package notifications

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"sync"
	"time"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/crypto/backup"
	"maunium.net/go/mautrix/crypto/goolm/session"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

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
}

type Participant struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

// One client per extension process, so a reused process keeps its connection
// to the homeserver instead of a fresh TLS handshake per push.
var httpClient = &http.Client{Timeout: 8 * time.Second}

func Fetch(ctx context.Context, req Request) (*Preview, error) {
	if req.RoomID == "" || req.EventID == "" || req.AccessToken == "" || !strings.HasPrefix(req.Homeserver, "https://") {
		return nil, errors.New("invalid notification context")
	}
	cli, err := mautrix.NewClient(req.Homeserver, req.UserID, req.AccessToken)
	if err != nil {
		return nil, err
	}
	cli.Client = httpClient
	ctx = mautrix.WithMaxRetries(ctx, 0)

	// Requests that don't depend on the event run while it downloads. Room
	// metadata shares one short budget and never reads the member list.
	metadataCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	var roomName event.RoomNameEventContent
	var roomAvatar event.RoomAvatarEventContent
	var roomMetadata sync.WaitGroup
	roomMetadata.Add(2)
	go func() {
		defer roomMetadata.Done()
		_ = cli.StateEvent(metadataCtx, req.RoomID, event.StateRoomName, "", &roomName)
	}()
	go func() {
		defer roomMetadata.Done()
		_ = cli.StateEvent(metadataCtx, req.RoomID, event.StateRoomAvatar, "", &roomAvatar)
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
	sender := evt.Sender.String()
	var senderAvatar id.ContentURIString
	// The sender's profile gets its own budget, since the room reads started earlier.
	profileCtx, cancelProfile := context.WithTimeout(ctx, 2*time.Second)
	defer cancelProfile()
	var senderProfile sync.WaitGroup
	senderProfile.Add(1)
	go func() {
		defer senderProfile.Done()
		if profile, err := cli.GetProfile(profileCtx, evt.Sender); err == nil {
			if name := strings.TrimSpace(profile.DisplayName); name != "" {
				sender = name
			}
			senderAvatar = id.ContentURIString(profile.AvatarURL.String())
		}
	}()

	content := evt.Content.VeryRaw
	typ := evt.Type.Type
	if typ == event.EventEncrypted.Type {
		var encrypted event.EncryptedEventContent
		if err = json.Unmarshal(content, &encrypted); err != nil {
			return nil, err
		}
		if encrypted.Algorithm != id.AlgorithmMegolmV1 {
			return nil, errors.New("unsupported encryption")
		}
		keyBytes, err := base64.StdEncoding.DecodeString(req.BackupKey)
		if err != nil {
			return nil, err
		}
		key, err := backup.MegolmBackupKeyFromBytes(keyBytes)
		if err != nil {
			return nil, err
		}
		backupLookup.Wait()
		if backupErr != nil {
			return nil, backupErr
		}
		if backupVersion.Algorithm != id.KeyBackupAlgorithmMegolmBackupV1 || string(backupVersion.AuthData.PublicKey) != base64.RawStdEncoding.EncodeToString(key.PublicKey().Bytes()) {
			return nil, errors.New("backup key mismatch")
		}
		data, err := cli.GetKeyBackupForRoomAndSession(ctx, backupVersion.Version, req.RoomID, encrypted.SessionID)
		if err != nil {
			return nil, err
		}
		roomKey, err := data.SessionData.Decrypt(key)
		if err != nil {
			return nil, err
		}
		if roomKey.Algorithm != id.AlgorithmMegolmV1 || (encrypted.SenderKey != "" && roomKey.SenderKey != encrypted.SenderKey) {
			return nil, errors.New("session mismatch")
		}
		inbound, err := session.NewMegolmInboundSessionFromExport([]byte(roomKey.SessionKey))
		if err != nil {
			return nil, err
		}
		if inbound.ID() != encrypted.SessionID {
			return nil, errors.New("session ID mismatch")
		}
		plain, _, err := inbound.Decrypt(encrypted.MegolmCiphertext)
		if err != nil {
			return nil, err
		}
		var decrypted struct {
			RoomID  id.RoomID       `json:"room_id"`
			Type    string          `json:"type"`
			Content json.RawMessage `json:"content"`
		}
		if err = json.Unmarshal(plain, &decrypted); err != nil {
			return nil, err
		}
		if decrypted.RoomID != req.RoomID {
			return nil, errors.New("decrypted room mismatch")
		}
		typ, content = decrypted.Type, decrypted.Content
	}
	var body string
	var targetEventID id.EventID
	if typ == event.EventReaction.Type {
		var reaction event.ReactionEventContent
		if err = json.Unmarshal(content, &reaction); err != nil {
			return nil, err
		}
		if evt.Sender == req.UserID || reaction.RelatesTo.Type != event.RelAnnotation ||
			reaction.RelatesTo.EventID == "" || strings.TrimSpace(reaction.RelatesTo.Key) == "" {
			return nil, errors.New("invalid reaction notification")
		}
		target, err := cli.GetEvent(ctx, req.RoomID, reaction.RelatesTo.EventID)
		if err != nil {
			return nil, err
		}
		if target.ID != reaction.RelatesTo.EventID || target.Sender != req.UserID ||
			(target.RoomID != "" && target.RoomID != req.RoomID) ||
			(target.Type != event.EventMessage && target.Type != event.EventEncrypted && target.Type != event.EventSticker) {
			return nil, errors.New("reaction is not to your message")
		}
		body = "Reacted " + reaction.RelatesTo.Key + " to your message"
		targetEventID = target.ID
	} else if typ != event.EventMessage.Type && typ != event.EventSticker.Type {
		return nil, errors.New("not a message")
	} else {
		var message event.MessageEventContent
		if err = json.Unmarshal(content, &message); err != nil {
			return nil, err
		}
		if message.NewContent != nil {
			message = *message.NewContent
		}
		message.RemoveReplyFallback()
		body = message.Body
		switch message.MsgType {
		case event.MsgImage:
			body = "Photo"
		case event.MsgVideo:
			body = "Video"
		case event.MsgAudio:
			body = "Audio message"
		case event.MsgFile:
			body = "File: " + body
		}
		if typ == event.EventSticker.Type {
			body = "Sticker"
		}
		if strings.TrimSpace(body) == "" {
			body = "New message"
		}
	}
	roomMetadata.Wait()
	senderProfile.Wait()
	title := sender
	name := strings.TrimSpace(roomName.Name)
	isGroup := name != "" && name != sender
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
		TargetEventID: targetEventID}
	var extras sync.WaitGroup
	extras.Add(1)
	go func() {
		defer extras.Done()
		preview.Avatar = fetchAvatar(ctx, cli, avatarURL)
	}()
	if isGroup {
		extras.Add(1)
		go func() {
			defer extras.Done()
			preview.Recipients = fetchRecipients(ctx, cli, req.RoomID, req.UserID, evt.Sender)
		}()
	}
	extras.Wait()
	return preview, nil
}

func fetchAvatar(ctx context.Context, cli *mautrix.Client, uri id.ContentURIString) []byte {
	parsed, err := uri.Parse()
	if err != nil || parsed.IsEmpty() {
		return nil
	}
	avatarCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	// Authenticated Matrix media stays on the homeserver. A small thumbnail
	// bounds both the extension's memory use and its image-decoding work.
	resp, err := cli.DownloadThumbnail(avatarCtx, parsed, 128, 128,
		mautrix.DownloadThumbnailExtra{Method: "scale"})
	if err != nil {
		return nil
	}
	defer resp.Body.Close()
	const maximumBytes = 256 * 1024
	if resp.StatusCode != http.StatusOK || resp.ContentLength > maximumBytes {
		return nil
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, maximumBytes+1))
	if err != nil || len(data) > maximumBytes || !strings.HasPrefix(http.DetectContentType(data), "image/") {
		return nil
	}
	return data
}

func truncate(s string, limit int) string {
	runes := []rune(s)
	if len(runes) > limit {
		return string(runes[:limit]) + "…"
	}
	return s
}
