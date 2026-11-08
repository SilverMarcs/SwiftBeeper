package dispatch

import (
	"context"
	"encoding/json"
	"fmt"

	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

// getMessagesLimit bounds one lookup. The app asks only for quoted messages
// older than its loaded timeline, a handful per page.
const getMessagesLimit = 100

// eventByIDSelect reads events without the timeline join, so a message the
// local timeline doesn't hold (such as a fetched thread reply) still resolves.
const eventByIDSelect = `
	SELECT rowid, 0,
	       room_id, event_id, sender, type, state_key, timestamp, content, decrypted, decrypted_type,
	       unsigned, local_content, transaction_id, redacted_by, relates_to, relation_type,
	       megolm_session_id, decryption_error, send_error, reactions, last_edit_rowid, unread_type
	FROM event
	WHERE room_id = ? AND event_id IN (%s)
`

// getMessages maps specific messages from the local database, for replies
// that quote a message older than the loaded timeline. One indexed query per
// call; it never touches the network.
func (s *Dispatcher) getMessages(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID     string   `json:"chatID"`
		MessageIDs []string `json:"messageIDs"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID, err := required(req.ChatID, "chatID")
	if err != nil {
		return nil, err
	}
	roomID := id.RoomID(chatID)
	args := []any{roomID}
	seen := make(map[string]bool, len(req.MessageIDs))
	for _, messageID := range req.MessageIDs {
		if messageID == "" || seen[messageID] {
			continue
		}
		seen[messageID] = true
		args = append(args, messageID)
		if len(args) > getMessagesLimit {
			break
		}
	}
	output := wire.GetMessagesOutput{Items: []wire.Message{}}
	if len(args) == 1 {
		return output, nil
	}
	events, err := s.queryEvents(ctx, fmt.Sprintf(eventByIDSelect, sqlSlots(len(args)-1)), args...)
	if err != nil {
		return nil, fmt.Errorf("failed to read messages: %w", err)
	}
	if output.Items, err = s.mapEvents(ctx, roomID, events); err != nil {
		return nil, err
	}
	return output, nil
}
