package dispatch

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strconv"
	"time"

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

// listMessages reads one page of the local timeline, newest first: the newest
// page, the page older than a cursor, the page newer than one, or a window
// around a message. Matrix sync owns ingestion; paging never touches the
// network. Older history arrives only through loadServerHistory, which the
// user asks for explicitly.
func (s *Dispatcher) listMessages(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID string `json:"chatID"`
		// Timeline position of the oldest message already shown.
		Cursor string `json:"cursor"`
		// Timeline position of the newest message already shown, for the
		// page after it.
		After string `json:"after"`
		// A message to read around, such as a search result.
		Around string `json:"around"`
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

	room, err := s.rt.Client().DB.Room.Get(ctx, roomID)
	if err != nil {
		return nil, fmt.Errorf("failed to get room: %w", err)
	} else if room == nil {
		return nil, errors.New("Chat not found")
	}

	reads, _ := s.loadLastReadSortKeys(ctx, roomID)
	lastRead, _ := strconv.ParseInt(reads[roomID], 10, 64)
	var events []*database.Event
	var hasMore, hasMoreNewer bool
	isPartial := req.Around != "" || req.After != ""
	switch {
	case req.Around != "":
		events, hasMore, hasMoreNewer, err = s.loadTimelineAround(ctx, roomID, id.EventID(req.Around))
	case req.After != "":
		var after int64
		if after, err = strconv.ParseInt(req.After, 10, 64); err != nil {
			return nil, fmt.Errorf("invalid after cursor: %w", err)
		}
		events, hasMoreNewer, err = s.loadNewerTimelineEvents(ctx, roomID, after, messagePageSize)
		// The older side is already shown.
		hasMore = true
	default:
		events, hasMore, err = s.loadTimelineEvents(ctx, roomID, before, req.Cursor != "")
	}
	if err != nil {
		return nil, err
	}
	if err = s.populateLastEditRefs(ctx, events); err != nil {
		return nil, err
	}
	members := s.loadMembersForEvents(ctx, events)[roomID]
	reactions, err := s.loadReactionMap(ctx, roomID, events)
	if err != nil {
		return nil, err
	}
	messages := make([]wire.Message, 0, messagePageSize)
	oldest := before
	for index, evt := range events {
		oldest = int64(evt.TimelineRowID)
		mapped, err := s.mapEventToMessage(evt, members, reactions)
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

	s.applyThreadSummaries(ctx, roomID, events, messages)
	s.applyDeliveryStatuses(ctx, roomID, messages)

	output := wire.ListMessagesOutput{
		Items:        messages,
		HasMore:      hasMore,
		HasMoreNewer: hasMoreNewer,
		OldestCursor: strconv.FormatInt(oldest, 10),
		// Unknown until the server reports the start of the room, so an
		// unpaginated room offers history.
		HasServerHistory: room.PrevBatch != database.PrevBatchPaginationComplete,
	}
	if isPartial {
		if len(events) > 0 {
			output.NewestCursor = strconv.FormatInt(int64(events[0].TimelineRowID), 10)
		} else {
			output.NewestCursor = req.After
		}
	}
	// The app reads the others' positions only with the newest page.
	if req.Cursor == "" && !isPartial {
		output.ReadReceipts = s.loadReadReceipts(ctx, roomID)
	}
	return output, nil
}

// loadServerHistory fetches older history from the homeserver into the local
// timeline, where listMessages pages it like any other row. It requests pages
// until one holds a message, or the room's start, so a press never yields only
// state events.
func (s *Dispatcher) loadServerHistory(ctx context.Context, input json.RawMessage) (any, error) {
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
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	for {
		resp, err := s.rt.Client().PaginateServer(ctx, id.RoomID(chatID), messagePageSize, false)
		if err != nil {
			return nil, err
		}
		if !resp.HasMore || slices.ContainsFunc(resp.Events, isHistoryMessage) {
			return wire.LoadServerHistoryOutput{HasMore: resp.HasMore}, nil
		}
	}
}

// isHistoryMessage reports a message or sticker the main timeline shows,
// excluding edits and thread replies. Encrypted events count even before their
// keys arrive, so missing keys cannot keep pagination running through the
// whole room.
func isHistoryMessage(evt *database.Event) bool {
	switch evt.Type {
	case event.EventMessage.Type, event.EventSticker.Type, event.EventEncrypted.Type:
		return evt.RelationType != event.RelReplace && !isHiddenThreadReply(evt)
	}
	return false
}

// timelineMessageSQL keeps the rows the main timeline shows. SQLite skips
// state/reaction/edit rows, and thread replies not sent to the chat, before
// materializing a page.
const timelineMessageSQL = ` AND (event.type IN ('m.room.message','m.sticker') OR event.decrypted_type IN ('m.room.message','m.sticker')) AND (relation_type IS NULL OR relation_type<>'m.replace') AND NOT ` + hiddenThreadReplySQL

// loadTimelineEvents reads up to one page plus one event older than before
// (or the newest without one), newest first.
func (s *Dispatcher) loadTimelineEvents(ctx context.Context, roomID id.RoomID, before int64, hasBefore bool) ([]*database.Event, bool, error) {
	const limit = messagePageSize + 1
	query := timelineSelectBase + timelineMessageSQL + ` AND (?=0 OR timeline.rowid<?) ORDER BY timeline.rowid DESC LIMIT ?`
	events, err := s.queryEvents(ctx, query, roomID, hasBefore, before, limit)
	if err != nil {
		return nil, false, fmt.Errorf("failed to query timeline: %w", err)
	}
	return events, len(events) == limit, nil
}

// loadNewerTimelineEvents reads up to limit events newer than after, newest
// first, and whether more follow them.
func (s *Dispatcher) loadNewerTimelineEvents(ctx context.Context, roomID id.RoomID, after int64, limit int) ([]*database.Event, bool, error) {
	query := timelineSelectBase + timelineMessageSQL + ` AND timeline.rowid>? ORDER BY timeline.rowid ASC LIMIT ?`
	events, err := s.queryEvents(ctx, query, roomID, after, limit+1)
	if err != nil {
		return nil, false, fmt.Errorf("failed to query timeline: %w", err)
	}
	hasMore := len(events) > limit
	if hasMore {
		events = events[:limit]
	}
	slices.Reverse(events)
	return events, hasMore, nil
}

// loadTimelineAround reads a page centered on a message, newest first: half
// a page newer than it, then it and the older events. The caller's page limit
// trims the older side.
func (s *Dispatcher) loadTimelineAround(ctx context.Context, roomID id.RoomID, eventID id.EventID) (events []*database.Event, hasMore, hasMoreNewer bool, err error) {
	findAnchor := func() (anchor int64, err error) {
		err = s.rt.Client().DB.QueryRow(ctx, `SELECT timeline.rowid FROM timeline JOIN event ON event.rowid=timeline.event_rowid
			WHERE timeline.room_id=? AND event.event_id=?`, roomID, eventID).Scan(&anchor)
		return
	}
	anchor, err := findAnchor()
	// A bookmark can be older than the stored timeline; page back for it.
	if errors.Is(err, sql.ErrNoRows) {
		if err = s.pageTimelineUntil(ctx, roomID, eventID, bookmarkHistoryPages); err != nil {
			return nil, false, false, fmt.Errorf("failed to load the message's history: %w", err)
		}
		anchor, err = findAnchor()
	}
	if errors.Is(err, sql.ErrNoRows) {
		return nil, false, false, errors.New("Message not found")
	} else if err != nil {
		return nil, false, false, fmt.Errorf("failed to find message: %w", err)
	}
	newer, hasMoreNewer, err := s.loadNewerTimelineEvents(ctx, roomID, anchor, messagePageSize/2)
	if err != nil {
		return nil, false, false, err
	}
	older, hasMore, err := s.loadTimelineEvents(ctx, roomID, anchor+1, true)
	if err != nil {
		return nil, false, false, err
	}
	return append(newer, older...), hasMore, hasMoreNewer, nil
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

// loadMembersForEvents resolves profiles, per room, for only the senders in
// this batch, not every member of their rooms. Member events also need the
// affected user's display name. A chat's participants are only a small
// avatar sample, so each message carries its sender's profile from here.
func (s *Dispatcher) loadMembersForEvents(ctx context.Context, events []*database.Event) map[id.RoomID]map[string]wire.User {
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
	profiles := make(map[id.RoomID]map[string]wire.User)
	if len(keys) == 0 {
		return profiles
	}
	members, err := s.rt.Client().DB.CurrentState.GetMany(ctx, keys)
	if err != nil {
		return profiles
	}
	self := string(s.rt.Client().Account.UserID)
	for _, member := range members {
		if member.StateKey == nil {
			continue
		}
		var content event.MemberEventContent
		if json.Unmarshal(member.GetContent(), &content) != nil {
			continue
		}
		if profiles[member.RoomID] == nil {
			profiles[member.RoomID] = make(map[string]wire.User)
		}
		profiles[member.RoomID][*member.StateKey] = userFromMemberEvent(*member.StateKey, content, self)
	}
	return profiles
}
