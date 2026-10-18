// Package notifications decrypts one notified event without opening a database,
// starting sync, or modifying the app's Olm account.
package notifications

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"strings"
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
	Title string `json:"title"`
	Body  string `json:"body"`
}

func Fetch(ctx context.Context, req Request) (*Preview, error) {
	if req.RoomID == "" || req.EventID == "" || req.AccessToken == "" || !strings.HasPrefix(req.Homeserver, "https://") {
		return nil, errors.New("invalid notification context")
	}
	cli, err := mautrix.NewClient(req.Homeserver, req.UserID, req.AccessToken)
	if err != nil {
		return nil, err
	}
	cli.Client = &http.Client{Timeout: 8 * time.Second}
	defer cli.Client.CloseIdleConnections()
	ctx = mautrix.WithMaxRetries(ctx, 0)
	evt, err := cli.GetEvent(ctx, req.RoomID, req.EventID)
	if err != nil {
		return nil, err
	}
	if evt.ID != req.EventID || (evt.RoomID != "" && evt.RoomID != req.RoomID) {
		return nil, errors.New("event mismatch")
	}
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
		version, err := cli.GetKeyBackupLatestVersion(ctx)
		if err != nil {
			return nil, err
		}
		if version.Algorithm != id.KeyBackupAlgorithmMegolmBackupV1 || string(version.AuthData.PublicKey) != base64.RawStdEncoding.EncodeToString(key.PublicKey().Bytes()) {
			return nil, errors.New("backup key mismatch")
		}
		data, err := cli.GetKeyBackupForRoomAndSession(ctx, version.Version, req.RoomID, encrypted.SessionID)
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
	if typ != event.EventMessage.Type && typ != event.EventSticker.Type {
		return nil, errors.New("not a message")
	}
	var message event.MessageEventContent
	if err = json.Unmarshal(content, &message); err != nil {
		return nil, err
	}
	if message.NewContent != nil {
		message = *message.NewContent
	}
	message.RemoveReplyFallback()
	body := message.Body
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
	// Sender lookup is optional and bounded; a slow profile must not hide a
	// successfully decrypted message near the extension's time limit.
	title := evt.Sender.String()
	profileCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	if profile, err := cli.GetProfile(profileCtx, evt.Sender); err == nil && profile.DisplayName != "" {
		title = profile.DisplayName
	}
	return &Preview{Title: truncate(title, 120), Body: truncate(body, 500)}, nil
}

func truncate(s string, limit int) string {
	runes := []rune(s)
	if len(runes) > limit {
		return string(runes[:limit]) + "…"
	}
	return s
}
