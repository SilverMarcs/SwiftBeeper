package dispatch

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"

	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

// markChatRead sends a read receipt for the latest event in the room.
func (s *Dispatcher) markChatRead(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID string `json:"chatID,omitempty"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID, err := required(req.ChatID, "chatID")
	if err != nil {
		return nil, err
	}

	cli := s.rt.Client()
	roomID := id.RoomID(chatID)
	var latestEventID id.EventID
	err = cli.DB.QueryRow(ctx, `SELECT event.event_id FROM timeline
		JOIN event ON event.rowid = timeline.event_rowid
		WHERE timeline.room_id = ? ORDER BY timeline.rowid DESC LIMIT 1`, roomID).Scan(&latestEventID)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return nil, fmt.Errorf("failed to find latest message: %w", err)
	}
	if latestEventID != "" {
		if err = cli.Client.MarkRead(ctx, roomID, latestEventID); err != nil {
			return nil, fmt.Errorf("failed to send read receipt: %w", err)
		}
		// Best effort: the read receipt is the important part.
		_ = cli.Client.SetRoomAccountData(ctx, roomID, "m.fully_read", map[string]any{"event_id": latestEventID})
	}
	if err = s.setChatMarkedUnread(ctx, roomID, false); err != nil {
		return nil, err
	}
	return wire.Success, nil
}

func (s *Dispatcher) markChatUnread(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID string `json:"chatID"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID, err := required(req.ChatID, "chatID")
	if err != nil {
		return nil, err
	}
	if err = s.setChatMarkedUnread(ctx, id.RoomID(chatID), true); err != nil {
		return nil, err
	}
	return s.getChat(ctx, input)
}

// loadLastReadSortKeys returns the timeline position of the user's own read
// receipt in each of the given rooms, or every room when none are given.
func (s *Dispatcher) loadLastReadSortKeys(ctx context.Context, roomIDs ...id.RoomID) (map[id.RoomID]string, error) {
	cli := s.rt.Client()
	if cli == nil || cli.Account == nil {
		return map[id.RoomID]string{}, nil
	}
	query := `
		SELECT r.room_id, t.rowid
		FROM receipt r
		JOIN event e ON e.event_id = r.event_id AND e.room_id = r.room_id
		JOIN timeline t ON t.event_rowid = e.rowid AND t.room_id = r.room_id
		WHERE r.user_id = ? AND r.receipt_type = 'm.read'
	`
	args := []any{cli.Account.UserID}
	if len(roomIDs) > 0 {
		query += " AND r.room_id IN (" + sqlSlots(len(roomIDs)) + ")"
		for _, roomID := range roomIDs {
			args = append(args, roomID)
		}
	}
	rows, err := cli.DB.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make(map[id.RoomID]string)
	for rows.Next() {
		var roomIDRaw string
		var timelineRowID int64
		if rows.Scan(&roomIDRaw, &timelineRowID) != nil {
			continue
		}
		if timelineRowID > 0 {
			result[id.RoomID(roomIDRaw)] = strconv.FormatInt(timelineRowID, 10)
		}
	}
	return result, rows.Err()
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

// isUnreadAfter reports whether a message's sort key lies past a read
// receipt's position. Both are timeline row IDs in decimal.
func isUnreadAfter(sortKey string, lastRead int64) bool {
	position, _ := strconv.ParseInt(sortKey, 10, 64)
	return position > lastRead
}
