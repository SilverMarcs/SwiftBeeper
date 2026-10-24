package dispatch

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"strings"
	"time"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/compat"
)

// Keep the bridge-owned resolver payload in Go. Swift only needs to know that
// the image is a Reel placeholder, and which message to resolve.
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
		return compat.ActionSuccessOutput{Success: true}, nil
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
	return compat.ActionSuccessOutput{Success: true}, nil
}
