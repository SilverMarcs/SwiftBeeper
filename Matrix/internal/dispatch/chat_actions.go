package dispatch

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"strconv"
	"strings"
	"time"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/compat"
)

// muteChat toggles the mute state of a chat via the com.beeper.mute room account data.
func (s *Dispatcher) muteChat(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID string `json:"chatID,omitempty"`
		Muted  *bool  `json:"muted,omitempty"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID := strings.TrimSpace(req.ChatID)
	if chatID == "" {
		return nil, errors.New("chatID is required")
	}
	muted := true
	if req.Muted != nil {
		muted = *req.Muted
	}

	var content event.BeeperMuteEventContent
	if muted {
		content.MutedUntil = -1 // -1 means muted forever
	} else {
		content.MutedUntil = 0 // 0 means not muted
	}
	if err := s.rt.Client().Client.SetRoomAccountData(ctx, id.RoomID(chatID), event.AccountDataBeeperMute.Type, content); err != nil {
		return nil, fmt.Errorf("failed to set mute state: %w", err)
	}
	// The homeserver echoes room account data through sync, but a message can
	// arrive before that echo. Update the local view before Swift exports the
	// new mute preferences to the notification gateway.
	if cli := s.rt.Client(); cli != nil && cli.Account != nil {
		raw, marshalErr := json.Marshal(content)
		if marshalErr != nil {
			log.Printf("failed to encode local mute state for %s: %v", chatID, marshalErr)
		} else if _, cacheErr := cli.DB.AccountData.PutRoom(
			ctx,
			cli.Account.UserID,
			id.RoomID(chatID),
			event.AccountDataBeeperMute,
			raw,
		); cacheErr != nil {
			log.Printf("failed to cache local mute state for %s: %v", chatID, cacheErr)
		}
	}
	return compat.ActionSuccessOutput{Success: true}, nil
}

// markChatRead sends a read receipt for the latest message in the room.
func (s *Dispatcher) markChatRead(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID string `json:"chatID,omitempty"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID := strings.TrimSpace(req.ChatID)
	if chatID == "" {
		return nil, errors.New("chatID is required")
	}

	cli := s.rt.Client()
	roomID := id.RoomID(chatID)

	// Find the latest event in the timeline.
	latestEventID, err := s.findLatestEventID(ctx, roomID)
	if err != nil {
		return nil, err
	}
	if latestEventID == "" {
		return nil, errors.New("No messages in this chat")
	}

	// Send m.read receipt.
	if err := cli.Client.MarkRead(ctx, roomID, id.EventID(latestEventID)); err != nil {
		return nil, fmt.Errorf("failed to send read receipt: %w", err)
	}

	// Also clear the m.fully_read marker (read marker line).
	if err := cli.Client.SetRoomAccountData(ctx, roomID, "m.fully_read", map[string]any{
		"event_id": latestEventID,
	}); err != nil {
		// Non-fatal: the read receipt is the important part.
		_ = err
	}

	return compat.ActionSuccessOutput{Success: true}, nil
}

const latestTimelineEventQuery = `
	SELECT event.event_id
	FROM timeline
	JOIN event ON event.rowid = timeline.event_rowid
	WHERE timeline.room_id = ?
	ORDER BY timeline.rowid DESC
	LIMIT 1
`

func (s *Dispatcher) findLatestEventID(ctx context.Context, roomID id.RoomID) (string, error) {
	cli := s.rt.Client()
	var eventID string
	err := cli.DB.QueryRow(ctx, latestTimelineEventQuery, roomID).Scan(&eventID)
	if err != nil {
		return "", nil // No events found is not an error.
	}
	return eventID, nil
}

// loadLastReadByOther returns the furthest timeline position another person has
// read. Bridge bots are excluded: their receipts mean delivery, not reading.
func (s *Dispatcher) loadLastReadByOther(ctx context.Context, roomID id.RoomID) string {
	cli := s.rt.Client()
	if cli == nil || cli.Account == nil {
		return ""
	}
	const query = `
		SELECT COALESCE(MAX(t.rowid), 0)
		FROM receipt r
		JOIN event e ON e.event_id = r.event_id AND e.room_id = r.room_id
		JOIN timeline t ON t.event_rowid = e.rowid AND t.room_id = r.room_id
		WHERE r.room_id = ? AND r.receipt_type = 'm.read' AND r.user_id != ? AND t.rowid > 0
		  AND SUBSTR(SUBSTR(r.user_id,2,INSTR(r.user_id,':')-2),-3)<>'bot'
	`
	var maxRead int64
	if err := cli.DB.QueryRow(ctx, query, roomID, cli.Account.UserID).Scan(&maxRead); err != nil || maxRead == 0 {
		return ""
	}
	return strconv.FormatInt(maxRead, 10)
}

func (s *Dispatcher) archiveChat(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		Archived *bool  `json:"archived,omitempty"`
		ChatID   string `json:"chatID,omitempty"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID := strings.TrimSpace(req.ChatID)
	if chatID == "" {
		return nil, errors.New("chatID is required")
	}
	archived := true
	if req.Archived != nil {
		archived = *req.Archived
	}

	var content any = map[string]any{}
	if archived {
		content = map[string]any{"updated_ts": time.Now().UnixMilli()}
	}
	if err := s.rt.Client().Client.SetRoomAccountData(ctx, id.RoomID(chatID), "com.beeper.inbox.done", content); err != nil {
		return nil, fmt.Errorf("failed to set archive state: %w", err)
	}
	// Archive actions always use Beeper Archive. Unarchive also removes an
	// existing Low Priority tag, while preserving favorites and every other tag.
	if err := s.clearLowPriority(ctx, id.RoomID(chatID)); err != nil {
		return nil, fmt.Errorf("failed to remove low priority state: %w", err)
	}
	// Cache the new archive state before a concurrent message checks eligibility.
	if cli := s.rt.Client(); cli != nil && cli.Account != nil {
		raw, marshalErr := json.Marshal(content)
		if marshalErr == nil {
			_, cacheErr := cli.DB.AccountData.PutRoom(ctx, cli.Account.UserID, id.RoomID(chatID),
				event.Type{Type: "com.beeper.inbox.done", Class: event.AccountDataEventType}, raw)
			if cacheErr != nil {
				log.Printf("cache archive state: %v", cacheErr)
			}
		}
	}
	return compat.ActionSuccessOutput{Success: true}, nil
}

func (s *Dispatcher) clearLowPriority(ctx context.Context, roomID id.RoomID) error {
	cli := s.rt.Client()
	var raw []byte
	err := cli.DB.QueryRow(ctx, `SELECT content FROM room_account_data WHERE user_id=? AND room_id=? AND type='m.tag'`, cli.Account.UserID, roomID).Scan(&raw)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	} else if err != nil {
		return err
	}
	var tags event.TagEventContent
	if err := json.Unmarshal(raw, &tags); err != nil {
		return err
	}
	if _, exists := tags.Tags[event.RoomTagLowPriority]; !exists {
		return nil
	}
	if err := cli.Client.RemoveTag(ctx, roomID, event.RoomTagLowPriority); err != nil && !errors.Is(err, mautrix.MNotFound) {
		return err
	}
	delete(tags.Tags, event.RoomTagLowPriority)
	raw, err = json.Marshal(tags)
	if err != nil {
		return err
	}
	_, err = cli.DB.AccountData.PutRoom(ctx, cli.Account.UserID, roomID, event.AccountDataRoomTags, raw)
	return err
}
