package notifications

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"time"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/id"
)

// Apple needs real additional recipients for group communication presentation.
// Read only a bounded prefix of this room's response, with no per-member calls.
func fetchRecipients(ctx context.Context, cli *mautrix.Client, roomID id.RoomID, me, sender id.UserID) []Participant {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	_, resp, err := cli.MakeFullRequestWithResp(ctx, mautrix.FullRequest{
		Method:           http.MethodGet,
		URL:              cli.BuildClientURL("v3", "rooms", roomID, "joined_members"),
		DontReadResponse: true,
	})
	if err != nil {
		return nil
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil
	}
	decoder := json.NewDecoder(io.LimitReader(resp.Body, 64*1024))
	if token, err := decoder.Token(); err != nil || token != json.Delim('{') {
		return nil
	}
	if token, err := decoder.Token(); err != nil || token != "joined" {
		return nil
	}
	if token, err := decoder.Token(); err != nil || token != json.Delim('{') {
		return nil
	}
	recipients := make([]Participant, 0, 8)
	for decoder.More() && len(recipients) < 8 {
		token, err := decoder.Token()
		if err != nil {
			break
		}
		userID, ok := token.(string)
		if !ok {
			break
		}
		var member struct {
			Name string `json:"display_name"`
		}
		if decoder.Decode(&member) != nil {
			break
		}
		if userID == "" || userID == string(me) || userID == string(sender) {
			continue
		}
		name := strings.TrimSpace(member.Name)
		if name == "" {
			name = userID
		}
		recipients = append(recipients, Participant{ID: userID, Name: truncate(name, 120)})
	}
	return recipients
}

// fetchAvatar downloads a small thumbnail of uri for the notification's
// sender or room picture, or returns nil.
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
