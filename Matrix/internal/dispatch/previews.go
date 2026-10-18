package dispatch

import (
	"context"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
	"maunium.net/go/mautrix/id"
)

// RefreshPreview persists a usable message already read locally, including
// historical messages with negative timeline positions. It never uses network.
func (s *Dispatcher) RefreshPreview(ctx context.Context, roomID id.RoomID, events []*database.Event) {
	var newest *database.Event
	for _, evt := range events {
		if evt.CanUseForPreview() && (newest == nil || evt.TimelineRowID > newest.TimelineRowID) {
			newest = evt
		}
	}
	if newest == nil {
		return
	}
	cli := s.rt.Client()
	changed, err := cli.DB.Room.UpdatePreviewIfLaterOnTimeline(ctx, roomID, newest.RowID)
	if err != nil || !changed {
		return
	}
	if room, err := cli.DB.Room.Get(ctx, roomID); err == nil && room != nil {
		cli.EventHandler(&jsoncmd.SyncComplete{Rooms: map[id.RoomID]*jsoncmd.SyncRoom{roomID: {Meta: room}}})
	}
}

func (s *Dispatcher) RecentRoomMessages(ctx context.Context, roomID id.RoomID, limit int) ([]*database.Event, error) {
	rows, err := s.rt.Client().DB.Query(ctx, timelineSelectBase+` AND event.type IN ('m.room.encrypted','m.room.message','m.sticker') ORDER BY timeline.rowid DESC LIMIT ?`, roomID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var events []*database.Event
	for rows.Next() {
		evt := &database.Event{}
		if _, err = evt.Scan(rows); err != nil {
			return nil, err
		}
		events = append(events, evt)
	}
	return events, rows.Err()
}
