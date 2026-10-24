package notifications

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/crypto/backup"
	"maunium.net/go/mautrix/crypto/goolm/session"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

// decryptWithBackup decrypts a Megolm event with its session from the key
// backup, returning the plaintext event type and content. backupVersion waits
// for the backup lookup that Fetch started early.
func decryptWithBackup(ctx context.Context, cli *mautrix.Client, req Request, content json.RawMessage,
	backupVersion func() (*mautrix.RespRoomKeysVersion[backup.MegolmAuthData], error)) (string, json.RawMessage, error) {
	var encrypted event.EncryptedEventContent
	if err := json.Unmarshal(content, &encrypted); err != nil {
		return "", nil, err
	}
	if encrypted.Algorithm != id.AlgorithmMegolmV1 {
		return "", nil, errors.New("unsupported encryption")
	}
	keyBytes, err := base64.StdEncoding.DecodeString(req.BackupKey)
	if err != nil {
		return "", nil, err
	}
	key, err := backup.MegolmBackupKeyFromBytes(keyBytes)
	if err != nil {
		return "", nil, err
	}
	version, err := backupVersion()
	if err != nil {
		return "", nil, err
	}
	if version.Algorithm != id.KeyBackupAlgorithmMegolmBackupV1 || string(version.AuthData.PublicKey) != base64.RawStdEncoding.EncodeToString(key.PublicKey().Bytes()) {
		return "", nil, errors.New("backup key mismatch")
	}
	data, err := cli.GetKeyBackupForRoomAndSession(ctx, version.Version, req.RoomID, encrypted.SessionID)
	if err != nil {
		return "", nil, err
	}
	roomKey, err := data.SessionData.Decrypt(key)
	if err != nil {
		return "", nil, err
	}
	if roomKey.Algorithm != id.AlgorithmMegolmV1 || (encrypted.SenderKey != "" && roomKey.SenderKey != encrypted.SenderKey) {
		return "", nil, errors.New("session mismatch")
	}
	inbound, err := session.NewMegolmInboundSessionFromExport([]byte(roomKey.SessionKey))
	if err != nil {
		return "", nil, err
	}
	if inbound.ID() != encrypted.SessionID {
		return "", nil, errors.New("session ID mismatch")
	}
	plain, _, err := inbound.Decrypt(encrypted.MegolmCiphertext)
	if err != nil {
		return "", nil, err
	}
	var decrypted struct {
		RoomID  id.RoomID       `json:"room_id"`
		Type    string          `json:"type"`
		Content json.RawMessage `json:"content"`
	}
	if err = json.Unmarshal(plain, &decrypted); err != nil {
		return "", nil, err
	}
	if decrypted.RoomID != req.RoomID {
		return "", nil, errors.New("decrypted room mismatch")
	}
	return decrypted.Type, decrypted.Content, nil
}
