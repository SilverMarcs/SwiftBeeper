package dispatch

import (
	"context"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"maunium.net/go/mautrix/id"
)

// unreadPosition prefers the actual receipt. When this device has no retained
// receipt event, the room's unread count bounds the fallback to recent incoming
// messages instead of treating all retained history as unread.
func (s *Dispatcher) unreadPosition(ctx context.Context, room *database.Room, lastRead int64) (int64, error) {
	if lastRead != 0 || room.UnreadMessages <= 0 {
		return lastRead, nil
	}
	var first int64
	query := `SELECT COALESCE(MIN(position),0) FROM (
		SELECT timeline.rowid AS position FROM timeline JOIN event ON event.rowid=timeline.event_rowid
		WHERE timeline.room_id=? ` + timelineMessageSQL + ` AND event.sender<>? AND event.redacted_by IS NULL
		ORDER BY timeline.rowid DESC LIMIT ?)`
	err := s.rt.Client().DB.QueryRow(ctx, query, id.RoomID(room.ID), s.rt.Client().Account.UserID, room.UnreadMessages).Scan(&first)
	if first > 0 {
		return first - 1, err
	}
	return 0, err
}
