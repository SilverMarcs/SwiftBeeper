package dispatch

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

const messagePageSize = 40

const timelineSelectBase = `
	SELECT event.rowid, timeline.rowid,
	       event.room_id, event_id, sender, type, state_key, timestamp, content, decrypted, decrypted_type,
	       unsigned, local_content, transaction_id, redacted_by, relates_to, relation_type,
	       megolm_session_id, decryption_error, send_error, reactions, last_edit_rowid, unread_type
	FROM timeline
	JOIN event ON event.rowid = timeline.event_rowid
	WHERE timeline.room_id = ?
`

// listMessages reads one page of the local timeline, newest first. Matrix sync
// owns ingestion; paging never touches the network.
func (s *Dispatcher) listMessages(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID string `json:"chatID"`
		// Timeline position of the oldest message already shown.
		Cursor string `json:"cursor"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID, err := required(req.ChatID, "chatID")
	if err != nil {
		return nil, err
	}
	roomID := id.RoomID(chatID)
	var before int64
	if req.Cursor != "" {
		if before, err = strconv.ParseInt(req.Cursor, 10, 64); err != nil {
			return nil, fmt.Errorf("invalid cursor: %w", err)
		}
	}

	if room, err := s.rt.Client().DB.Room.Get(ctx, roomID); err != nil {
		return nil, fmt.Errorf("failed to get room: %w", err)
	} else if room == nil {
		return nil, errors.New("Chat not found")
	}

	reads, _ := s.loadLastReadSortKeys(ctx, roomID)
	lastRead, _ := strconv.ParseInt(reads[roomID], 10, 64)
	events, hasMore, err := s.loadTimelineEvents(ctx, roomID, before)
	if err != nil {
		return nil, err
	}
	if err = s.populateLastEditRefs(ctx, events); err != nil {
		return nil, err
	}
	names := s.loadNamesForEvents(ctx, events)[roomID]
	reactions, err := s.loadReactionMap(ctx, roomID, events)
	if err != nil {
		return nil, err
	}
	messages := make([]wire.Message, 0, messagePageSize)
	oldest := before
	for index, evt := range events {
		oldest = int64(evt.TimelineRowID)
		mapped, err := s.mapEventToMessage(evt, names, reactions)
		if err != nil {
			continue
		}
		if lastRead != 0 && !mapped.IsSender {
			mapped.IsUnread = isUnreadAfter(mapped.SortKey, lastRead)
		}
		messages = append(messages, mapped)
		if len(messages) == messagePageSize {
			hasMore = hasMore || index < len(events)-1
			break
		}
	}

	output := wire.ListMessagesOutput{
		Items:        messages,
		HasMore:      hasMore,
		OldestCursor: strconv.FormatInt(oldest, 10),
	}
	// The app reads the other side's position only with the newest page.
	if before == 0 {
		output.LastReadByOtherSortKey = s.loadLastReadByOther(ctx, roomID)
	}
	return output, nil
}

// loadTimelineEvents reads up to one page plus one event older than before
// (or the newest when before is 0), newest first.
func (s *Dispatcher) loadTimelineEvents(ctx context.Context, roomID id.RoomID, before int64) ([]*database.Event, bool, error) {
	const limit = messagePageSize + 1
	// SQLite skips state/reaction/edit rows before materializing the local page.
	query := timelineSelectBase + ` AND (event.type IN ('m.room.message','m.sticker') OR event.decrypted_type IN ('m.room.message','m.sticker')) AND (relation_type IS NULL OR relation_type<>'m.replace')` +
		` AND (?=0 OR timeline.rowid<?) ORDER BY timeline.rowid DESC LIMIT ?`
	events, err := s.queryEvents(ctx, query, roomID, before, before, limit)
	if err != nil {
		return nil, false, fmt.Errorf("failed to query timeline: %w", err)
	}
	return events, len(events) == limit, nil
}

// RecentRoomMessages returns the room's newest message-like events, including
// undecrypted ones, newest first.
func (s *Dispatcher) RecentRoomMessages(ctx context.Context, roomID id.RoomID, limit int) ([]*database.Event, error) {
	return s.queryEvents(ctx, timelineSelectBase+` AND event.type IN ('m.room.encrypted','m.room.message','m.sticker') ORDER BY timeline.rowid DESC LIMIT ?`, roomID, limit)
}

func (s *Dispatcher) queryEvents(ctx context.Context, query string, args ...any) ([]*database.Event, error) {
	rows, err := s.rt.Client().DB.Query(ctx, query, args...)
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

// populateLastEditRefs attaches each event's latest unredacted edit, so the
// mapped message shows the edited content.
func (s *Dispatcher) populateLastEditRefs(ctx context.Context, events []*database.Event) error {
	cli := s.rt.Client()
	if cli == nil || len(events) == 0 {
		return nil
	}

	byEditRowID := make(map[database.EventRowID][]*database.Event)
	editRowIDs := make([]database.EventRowID, 0)
	for _, evt := range events {
		if evt == nil || evt.LastEditRowID == nil {
			continue
		}
		editRowID := *evt.LastEditRowID
		if editRowID <= 0 || editRowID == evt.RowID {
			continue
		}
		if _, ok := byEditRowID[editRowID]; !ok {
			editRowIDs = append(editRowIDs, editRowID)
		}
		byEditRowID[editRowID] = append(byEditRowID[editRowID], evt)
	}
	if len(editRowIDs) == 0 {
		return nil
	}

	editEvents, err := cli.DB.Event.GetByRowIDs(ctx, editRowIDs...)
	if err != nil {
		return fmt.Errorf("failed to load edited message references: %w", err)
	}
	editByRowID := make(map[database.EventRowID]*database.Event, len(editEvents))
	for _, evt := range editEvents {
		if evt != nil {
			editByRowID[evt.RowID] = evt
		}
	}
	for editRowID, targets := range byEditRowID {
		editEvt := editByRowID[editRowID]
		if editEvt == nil || editEvt.RedactedBy != "" {
			continue
		}
		for _, target := range targets {
			target.LastEditRef = editEvt
		}
	}
	return nil
}

// populateTimelinePositions sets TimelineRowID on events loaded without the
// timeline join; events not on the timeline get zero.
func (s *Dispatcher) populateTimelinePositions(ctx context.Context, events []*database.Event) error {
	if len(events) == 0 {
		return nil
	}
	args := make([]any, len(events))
	byID := make(map[database.EventRowID]*database.Event, len(events))
	for i, evt := range events {
		args[i] = evt.RowID
		byID[evt.RowID] = evt
		evt.TimelineRowID = 0
	}
	rows, err := s.rt.Client().DB.Query(ctx, `SELECT event_rowid,rowid FROM timeline WHERE event_rowid IN (`+sqlSlots(len(args))+`)`, args...)
	if err != nil {
		return err
	}
	defer rows.Close()
	for rows.Next() {
		var rowID database.EventRowID
		var timelineID database.TimelineRowID
		if err = rows.Scan(&rowID, &timelineID); err != nil {
			return err
		}
		if evt := byID[rowID]; evt != nil {
			evt.TimelineRowID = timelineID
		}
	}
	return rows.Err()
}

// loadNamesForEvents resolves display names, per room, for only the senders
// in this batch, not every member of their rooms. Member events also need the
// affected user's display name.
func (s *Dispatcher) loadNamesForEvents(ctx context.Context, events []*database.Event) map[id.RoomID]map[string]string {
	keys := make([]database.RoomStateGUID, 0, len(events))
	seen := make(map[database.RoomStateGUID]bool)
	for _, evt := range events {
		users := []string{string(evt.Sender)}
		if evt.StateKey != nil {
			users = append(users, *evt.StateKey)
		}
		for _, user := range users {
			key := database.RoomStateGUID{RoomID: evt.RoomID, Type: event.StateMember, StateKey: user}
			if user != "" && !seen[key] {
				seen[key] = true
				keys = append(keys, key)
			}
		}
	}
	names := make(map[id.RoomID]map[string]string)
	if len(keys) == 0 {
		return names
	}
	members, err := s.rt.Client().DB.CurrentState.GetMany(ctx, keys)
	if err != nil {
		return names
	}
	for _, member := range members {
		if member.StateKey == nil {
			continue
		}
		var content event.MemberEventContent
		if json.Unmarshal(member.GetContent(), &content) != nil {
			continue
		}
		name := strings.TrimSpace(content.Displayname)
		if name == "" {
			name = *member.StateKey
		}
		if names[member.RoomID] == nil {
			names[member.RoomID] = make(map[string]string)
		}
		names[member.RoomID][*member.StateKey] = name
	}
	return names
}
