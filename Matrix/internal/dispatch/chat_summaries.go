package dispatch

import (
	"context"
	"encoding/json"
	"strconv"
	"strings"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
	"relay/core/internal/compat"
	"relay/core/internal/cursor"
)

type chatSummaryKey struct{}
type chatSummary struct {
	members        []compat.User
	accountMembers []compat.User
	total          int
	preview        *database.Event
	names          map[string]string
}

func sqlSlots(count int) string { return strings.TrimSuffix(strings.Repeat("?,", count), ",") }

func previewNumericKey(message compat.Message) int64 {
	value, _ := strconv.ParseInt(message.SortKey, 10, 64)
	return value
}

// One bounded member projection and one event batch for a page of rooms. Counts
// stay in SQLite; large groups do not materialize their whole membership in Go.
func (s *Dispatcher) loadChatSummaries(ctx context.Context, rooms []*database.Room, limit int, lookup *accountLookup, includePreview bool) (map[id.RoomID]*chatSummary, error) {
	result := make(map[id.RoomID]*chatSummary, len(rooms))
	if len(rooms) == 0 {
		return result, nil
	}
	args := make([]any, 0, len(rooms)+len(lookup.ByBridge)+2)
	for _, room := range rooms {
		result[room.ID] = &chatSummary{names: make(map[string]string)}
		args = append(args, room.ID)
	}
	ghostClauses := []string{"0"}
	for bridge := range lookup.ByBridge {
		ghostClauses = append(ghostClauses, "cs.state_key GLOB ?")
		args = append(args, "@"+bridge+"_*:*")
	}
	args = append(args, limit, limit)
	// Include the first bridge ghost even if it falls outside the avatar sample,
	// so a small participant limit cannot change a room's network/account.
	query := `WITH members AS (
        SELECT cs.room_id, cs.state_key, e.content,
          ROW_NUMBER() OVER (PARTITION BY cs.room_id ORDER BY COALESCE(NULLIF(TRIM(json_extract(e.content,'$.displayname')),''),cs.state_key),cs.state_key) AS rank,
          COUNT(*) OVER (PARTITION BY cs.room_id) AS total,
          (` + strings.Join(ghostClauses, " OR ") + `) AS ghost
        FROM current_state cs JOIN event e ON e.rowid=cs.event_rowid
        WHERE cs.room_id IN (` + sqlSlots(len(rooms)) + `) AND cs.event_type='m.room.member'
          AND COALESCE(NULLIF(cs.membership,''),json_extract(e.content,'$.membership')) IN ('join','invite')
          AND SUBSTR(SUBSTR(cs.state_key,2,INSTR(cs.state_key,':')-2),-3)<>'bot'
    ), first_ghost AS (SELECT room_id,MIN(rank) AS rank FROM members WHERE ghost GROUP BY room_id)
    SELECT m.room_id,m.state_key,m.content,m.rank,m.total FROM members m
      LEFT JOIN first_ghost g ON g.room_id=m.room_id
      WHERE ?<0 OR m.rank<=? OR m.rank=1 OR m.rank=g.rank ORDER BY m.room_id,m.rank`
	// Placeholder order follows SELECT before WHERE.
	roomArgs, ghostArgs := args[:len(rooms)], args[len(rooms):len(args)-2]
	ordered := append(append(append([]any{}, ghostArgs...), roomArgs...), args[len(args)-2:]...)
	rows, err := s.rt.Client().DB.Query(ctx, query, ordered...)
	if err != nil {
		return nil, err
	}
	self := string(s.rt.Client().Account.UserID)
	for rows.Next() {
		var roomID id.RoomID
		var userID string
		var content []byte
		var rank, total int
		if err = rows.Scan(&roomID, &userID, &content, &rank, &total); err != nil {
			rows.Close()
			return nil, err
		}
		summary := result[roomID]
		summary.total = total
		var member event.MemberEventContent
		if json.Unmarshal(content, &member) != nil {
			continue
		}
		user := userFromMemberEvent(userID, member, self)
		if limit < 0 || rank <= limit {
			summary.members = append(summary.members, user)
		}
		summary.accountMembers = append(summary.accountMembers, user)
		summary.names[user.ID] = user.FullName
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, err
	}
	if lookup.roomAccounts == nil {
		lookup.roomAccounts = make(map[id.RoomID]roomAccount)
	}
	for _, room := range rooms {
		account, network := inferAccountForRoom(room.ID, lookup)
		if foundAccount, foundNetwork, ok := inferAccountFromMembers(result[room.ID].accountMembers, self, lookup); ok {
			account, network = foundAccount, foundNetwork
		}
		lookup.roomAccounts[room.ID] = roomAccount{accountID: account, network: network}
	}
	if !includePreview {
		return result, nil
	}
	var ids []database.EventRowID
	for _, room := range rooms {
		if room.PreviewEventRowID > 0 {
			ids = append(ids, room.PreviewEventRowID)
		}
	}
	if len(ids) == 0 {
		return result, nil
	}
	events, err := s.rt.Client().DB.Event.GetByRowIDs(ctx, ids...)
	if err != nil {
		return nil, err
	}
	if err = s.populateLastEditRefs(ctx, events); err != nil {
		return nil, err
	}
	if err = s.populateTimelinePositions(ctx, events); err != nil {
		return nil, err
	}
	names := s.loadNamesForEvents(ctx, events)
	byID := make(map[database.EventRowID]*database.Event, len(events))
	for _, evt := range events {
		byID[evt.RowID] = evt
	}
	for _, room := range rooms {
		summary := result[room.ID]
		summary.preview = byID[room.PreviewEventRowID]
		if summary.preview != nil {
			for key, name := range names[room.ID] {
				summary.names[key] = name
			}
		}
	}
	return result, nil
}

func roomMatchesInbox(room *database.Room, state roomAccountDataState, inbox string) bool {
	switch inbox {
	case "primary":
		return !state.InArchive()
	case "archive":
		return state.InArchive()
	case "unread":
		return room.UnreadMessages > 0 || state.IsMarkedUnread
	default:
		return true
	}
}

func (s *Dispatcher) loadRoomPage(ctx context.Context, boundary *cursor.ChatCursor, direction string, scanned *cursor.ChatCursor) ([]*database.Room, error) {
	query := roomSelectBaseQuery + `WHERE sorting_timestamp>0 AND room_type<>'m.space'`
	var args []any
	if boundary != nil {
		if direction == "after" {
			query += ` AND (sorting_timestamp>? OR (sorting_timestamp=? AND room_id<?))`
		} else {
			query += ` AND (sorting_timestamp<? OR (sorting_timestamp=? AND room_id>?))`
		}
		args = append(args, boundary.TS, boundary.TS, boundary.RoomID)
	}
	if scanned != nil {
		query += ` AND (sorting_timestamp<? OR (sorting_timestamp=? AND room_id>?))`
		args = append(args, scanned.TS, scanned.TS, scanned.RoomID)
	}
	query += ` ORDER BY sorting_timestamp DESC,room_id ASC LIMIT ?`
	args = append(args, chatPageSize+1)
	rows, err := s.rt.Client().DB.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var rooms []*database.Room
	for rows.Next() {
		room := &database.Room{}
		if _, err = room.Scan(rows); err != nil {
			return nil, err
		}
		rooms = append(rooms, room)
	}
	return rooms, rows.Err()
}

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

// Resolve only senders represented by this page/event batch, not every member
// of their rooms. Member events also need the affected user's display name.
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
