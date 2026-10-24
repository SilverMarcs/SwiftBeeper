package dispatch

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/crypto/attachment"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

// LocalAsset returns a local file for Matrix media, downloading and
// decrypting it on the first request. The source is mxc:// or localmxc://.
func (s *Dispatcher) LocalAsset(ctx context.Context, source string) (string, error) {
	normalized := strings.TrimSpace(source)
	if strings.HasPrefix(normalized, "localmxc://") {
		normalized = "mxc://" + strings.TrimPrefix(normalized, "localmxc://")
	}
	parsedMXC := id.ContentURIString(normalized).ParseOrIgnore()
	if !parsedMXC.IsValid() {
		return "", errors.New("URL must be mxc:// or localmxc://")
	}

	cacheDir := filepath.Join(s.rt.DataDir(), "assets")
	sum := sha256.Sum256([]byte(normalized))
	plainPath := filepath.Join(cacheDir, hex.EncodeToString(sum[:]))
	decryptedPath := plainPath + ".decrypted"
	// A decrypted copy is always right. A plain copy is right only when the
	// media isn't encrypted, which the SDK's media table records.
	if _, err := os.Stat(decryptedPath); err == nil {
		return decryptedPath, nil
	}
	var encFile *attachment.EncryptedFile
	if media, err := s.rt.Client().DB.Media.Get(ctx, parsedMXC); err == nil && media != nil {
		encFile = media.EncFile
	}
	cachePath := plainPath
	if encFile != nil {
		cachePath = decryptedPath
	} else if _, err := os.Stat(plainPath); err == nil {
		return plainPath, nil
	}
	if err := os.MkdirAll(cacheDir, 0o700); err != nil {
		return "", fmt.Errorf("failed to create asset cache dir: %w", err)
	}

	resp, err := s.rt.Client().Client.Download(ctx, parsedMXC)
	if err != nil {
		return "", fmt.Errorf("failed to download asset: %w", err)
	}
	defer resp.Body.Close()
	if err = streamToCache(resp.Body, encFile, cacheDir, cachePath); err != nil {
		return "", err
	}
	return cachePath, nil
}

// streamToCache writes the download to cachePath, decrypting it on the way
// when encFile is set, so large media never sits in memory whole. It writes
// to a unique temporary file first, so concurrent requests for the same media
// can't interleave and a failed or tampered download never becomes the cache.
func streamToCache(body io.Reader, encFile *attachment.EncryptedFile, cacheDir, cachePath string) error {
	var source io.Reader = body
	var decrypter io.ReadCloser
	if encFile != nil {
		if err := encFile.PrepareForDecryption(); err != nil {
			return fmt.Errorf("failed to decrypt asset: %w", err)
		}
		decrypter = encFile.DecryptStream(body)
		source = decrypter
	}

	temp, err := os.CreateTemp(cacheDir, "download-*.tmp")
	if err != nil {
		return fmt.Errorf("failed to save downloaded asset: %w", err)
	}
	tempPath := temp.Name()
	defer os.Remove(tempPath) // No-op once renamed into place.

	_, err = io.Copy(temp, source)
	if closeErr := temp.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return fmt.Errorf("failed to read downloaded asset: %w", err)
	}
	// Closing the decrypter verifies the SHA-256 of the whole ciphertext.
	if decrypter != nil {
		if err = decrypter.Close(); err != nil {
			return fmt.Errorf("failed to decrypt asset: %w", err)
		}
	}
	if err = os.Rename(tempPath, cachePath); err != nil {
		return fmt.Errorf("failed to finalize cached asset: %w", err)
	}
	return nil
}

// unresolvedReelContent returns the bridge's resolver payload when the event
// is an Instagram Reel placeholder. The payload stays in Go: Swift only needs
// to know that the image is a Reel, and which message to resolve.
func unresolvedReelContent(raw json.RawMessage) json.RawMessage {
	var content struct {
		UnresolvedMedia json.RawMessage `json:"com.beeper.unresolved_media"`
		ExternalURL     string          `json:"external_url"`
	}
	if json.Unmarshal(raw, &content) != nil {
		return nil
	}
	var marker struct {
		Kind string `json:"kind"`
	}
	if json.Unmarshal(content.UnresolvedMedia, &marker) != nil || marker.Kind != "permanent" {
		return nil
	}
	link, err := url.Parse(content.ExternalURL)
	if err != nil || (link.Hostname() != "www.instagram.com" && link.Hostname() != "instagram.com") ||
		(!strings.HasPrefix(link.Path, "/reel/") && !strings.HasPrefix(link.Path, "/reels/")) {
		return nil
	}
	return content.UnresolvedMedia
}

// resolveMedia asks the room's Instagram bridge to replace a Reel placeholder
// with the actual video.
func (s *Dispatcher) resolveMedia(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID    id.RoomID  `json:"chatID"`
		MessageID id.EventID `json:"messageID"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	if req.ChatID == "" || req.MessageID == "" {
		return nil, errors.New("chatID and messageID are required")
	}
	ctx, cancel := context.WithTimeout(ctx, 45*time.Second)
	defer cancel()
	cli := s.rt.Client()
	evt, err := cli.DB.Event.GetByID(ctx, req.MessageID)
	if err != nil {
		return nil, err
	}
	if evt == nil || evt.RoomID != req.ChatID || evt.RedactedBy != "" {
		return nil, errors.New("Reel message is no longer available")
	}
	if err = s.populateLastEditRefs(ctx, []*database.Event{evt}); err != nil {
		return nil, err
	}
	payload := unresolvedReelContent(evt.GetContent())
	if payload == nil {
		// Sync may have resolved the message while its visibility delay ran.
		return wire.Success, nil
	}
	// Use this room's bridge and receiver, rather than choosing the user's
	// first Instagram login. State keys can differ between bridge versions.
	var raw []byte
	err = cli.DB.QueryRow(ctx, `SELECT e.content FROM current_state cs
		JOIN event e ON e.rowid=cs.event_rowid
		WHERE cs.room_id=? AND cs.event_type IN ('m.bridge','uk.half-shot.bridge')
		ORDER BY CASE cs.event_type WHEN 'm.bridge' THEN 0 ELSE 1 END LIMIT 1`, req.ChatID).Scan(&raw)
	if err != nil {
		return nil, errors.New("Instagram connection for this chat is unavailable")
	}
	var bridge struct {
		Name     string `json:"com.beeper.bridge_name"`
		Protocol struct {
			ID string `json:"id"`
		} `json:"protocol"`
		Channel struct {
			Receiver string `json:"fi.mau.receiver"`
		} `json:"channel"`
	}
	if json.Unmarshal(raw, &bridge) != nil {
		return nil, errors.New("Invalid Instagram connection metadata")
	}
	if bridge.Name == "" {
		bridge.Name = bridge.Protocol.ID
	}
	if bridge.Protocol.ID != "instagramgo" || bridge.Name == "" || bridge.Channel.Receiver == "" {
		return nil, errors.New("This connection does not support resolving Reels")
	}
	endpoint, err := url.Parse(cli.Client.BuildURL(mautrix.BaseURLPath{
		"_matrix", "client", "unstable", "com.beeper.bridge", bridge.Name,
		"_matrix", "provision", "v3", "resolve_media", req.MessageID,
	}))
	if err != nil {
		return nil, err
	}
	query := endpoint.Query()
	query.Set("user_id", string(cli.Account.UserID))
	query.Set("login_id", bridge.Channel.Receiver)
	endpoint.RawQuery = query.Encode()
	// The bridge emits an edit of the original event. Normal encrypted sync
	// persists it and updates the existing bubble; do not create a new message.
	_, err = cli.Client.MakeFullRequest(ctx, mautrix.FullRequest{
		Method: http.MethodPost, URL: endpoint.String(), MaxAttempts: 1,
		RequestJSON:       map[string]json.RawMessage{"com.beeper.unresolved_media": payload},
		ResponseSizeLimit: 64 * 1024,
	})
	if err != nil {
		return nil, err
	}
	return wire.Success, nil
}
