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
		WHERE r.user_id = ? AND r.receipt_type IN ('m.read','m.read.private')
		  AND r.thread_id IN ('','main')
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

// readReceiptMemberLimit is the most members a room may have for its read
// receipts to be loaded. Who has seen a message means little in a larger
// group, and its receipts arrive constantly. The app uses the same limit.
const readReceiptMemberLimit = 25

// loadReadReceipts returns how far each other person has read, by timeline
// position, named as the room knows them. Bridge bots are excluded: their
// receipts mean delivery, not reading. A room above readReceiptMemberLimit
// members returns none.
func (s *Dispatcher) loadReadReceipts(ctx context.Context, roomID id.RoomID) []wire.ReadReceipt {
	cli := s.rt.Client()
	if cli == nil || cli.Account == nil {
		return nil
	}
	if count, err := s.roomMemberCount(ctx, roomID); err != nil || count > readReceiptMemberLimit {
		return nil
	}
	// A user holds one receipt per thread; the furthest is how far they read.
	const query = `
		SELECT r.user_id, MAX(t.rowid),
		       COALESCE(NULLIF(TRIM(json_extract(member.content,'$.displayname')),''),'')
		FROM receipt r
		JOIN event e ON e.event_id = r.event_id AND e.room_id = r.room_id
		JOIN timeline t ON t.event_rowid = e.rowid AND t.room_id = r.room_id
		LEFT JOIN current_state cs ON cs.room_id = r.room_id AND cs.event_type = 'm.room.member' AND cs.state_key = r.user_id
		LEFT JOIN event member ON member.rowid = cs.event_rowid
		WHERE r.room_id = ? AND r.receipt_type = 'm.read' AND r.user_id != ? AND t.rowid > 0
		  AND SUBSTR(SUBSTR(r.user_id,2,INSTR(r.user_id,':')-2),-3)<>'bot'
		GROUP BY r.user_id
	`
	rows, err := cli.DB.Query(ctx, query, roomID, cli.Account.UserID)
	if err != nil {
		return nil
	}
	defer rows.Close()
	var receipts []wire.ReadReceipt
	for rows.Next() {
		var userID, name string
		var position int64
		if rows.Scan(&userID, &position, &name) != nil || position == 0 {
			continue
		}
		if name == "" {
			name = id.UserID(userID).Localpart()
		}
		receipts = append(receipts, wire.ReadReceipt{UserID: userID, Name: name, SortKey: strconv.FormatInt(position, 10)})
	}
	return receipts
}

// roomMemberCount counts a room's joined and invited members, bridge bots
// aside, as the chat summary's total does.
func (s *Dispatcher) roomMemberCount(ctx context.Context, roomID id.RoomID) (int, error) {
	const query = `
		SELECT COUNT(*)
		FROM current_state cs JOIN event e ON e.rowid = cs.event_rowid
		WHERE cs.room_id = ? AND cs.event_type = 'm.room.member'
		  AND COALESCE(NULLIF(cs.membership,''),json_extract(e.content,'$.membership')) IN ('join','invite')
		  AND SUBSTR(SUBSTR(cs.state_key,2,INSTR(cs.state_key,':')-2),-3)<>'bot'
	`
	var count int
	err := s.rt.Client().DB.QueryRow(ctx, query, roomID).Scan(&count)
	return count, err
}

// isUnreadAfter reports whether a message's sort key lies past a read
// receipt's position. Both are timeline row IDs in decimal.
func isUnreadAfter(sortKey string, lastRead int64) bool {
	position, _ := strconv.ParseInt(sortKey, 10, 64)
	return position > lastRead
}
