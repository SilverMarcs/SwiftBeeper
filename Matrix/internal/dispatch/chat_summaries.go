package dispatch

import (
	"context"
	"encoding/json"
	"slices"
	"strings"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

// One past the page size, to tell whether more rooms follow.
const roomPageSize = chatPageSize + 1

const roomSelectBaseQuery = `
	SELECT room_id, creation_content, tombstone_content, name, name_quality,
	       avatar, explicit_avatar, dm_user_id, topic, canonical_alias,
	       lazy_load_summary, encryption_event, has_member_list, preview_event_rowid, sorting_timestamp,
	       unread_highlights, unread_notifications, unread_messages, marked_unread, prev_batch
	FROM room
`

// roomPosition is a room's place in the sidebar order.
type roomPosition struct {
	ts     int64
	roomID string
}

type chatSummary struct {
	members  []wire.User
	isDirect bool
	// The shown members plus the first bridge ghost, for account inference.
	accountMembers []wire.User
	total          int
	preview        *database.Event
	names          map[string]string
}

// loadRoomPage returns the next rooms in sidebar order after position.
func (s *Dispatcher) loadRoomPage(ctx context.Context, position *roomPosition) ([]*database.Room, error) {
	query := roomSelectBaseQuery + `WHERE sorting_timestamp>0 AND room_type<>'m.space'`
	var args []any
	if position != nil {
		query += ` AND (sorting_timestamp<? OR (sorting_timestamp=? AND room_id>?))`
		args = append(args, position.ts, position.ts, position.roomID)
	}
	query += ` ORDER BY sorting_timestamp DESC,room_id ASC LIMIT ?`
	args = append(args, roomPageSize)
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

// loadChatSummaries runs one bounded member projection and one event batch for
// a page of rooms. Counts stay in SQLite; large groups do not materialize
// their whole membership in Go. It also records each room's account in
// lookup.roomAccounts.
func (s *Dispatcher) loadChatSummaries(ctx context.Context, rooms []*database.Room, limit int, lookup *accountLookup) (map[id.RoomID]*chatSummary, error) {
	result := make(map[id.RoomID]*chatSummary, len(rooms))
	if len(rooms) == 0 {
		return result, nil
	}
	roomArgs := make([]any, 0, len(rooms))
	for _, room := range rooms {
		result[room.ID] = &chatSummary{members: []wire.User{}, names: make(map[string]string)}
		roomArgs = append(roomArgs, room.ID)
	}
	ghostClauses := []string{"0"}
	var ghostArgs []any
	for bridge := range lookup.byBridge {
		ghostClauses = append(ghostClauses, "cs.state_key GLOB ?")
		ghostArgs = append(ghostArgs, "@"+bridge+"_*:*")
	}
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
      WHERE m.rank<=? OR m.rank=1 OR m.rank=g.rank ORDER BY m.room_id,m.rank`
	// Placeholder order follows SELECT before WHERE.
	args := append(append(ghostArgs, roomArgs...), limit)
	rows, err := s.rt.Client().DB.Query(ctx, query, args...)
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
		summary.isDirect = summary.isDirect || member.IsDirect
		user := userFromMemberEvent(userID, member, self)
		if rank <= limit {
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
	for _, room := range rooms {
		lookup.roomAccounts[room.ID] = inferAccountForRoom(room.ID, result[room.ID].accountMembers, lookup)
	}
	var previewRowIDs []database.EventRowID
	for _, room := range rooms {
		if room.PreviewEventRowID > 0 {
			previewRowIDs = append(previewRowIDs, room.PreviewEventRowID)
		}
	}
	if len(previewRowIDs) == 0 {
		return result, nil
	}
	events, err := s.rt.Client().DB.Event.GetByRowIDs(ctx, previewRowIDs...)
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
	byRowID := make(map[database.EventRowID]*database.Event, len(events))
	for _, evt := range events {
		byRowID[evt.RowID] = evt
	}
	for _, room := range rooms {
		summary := result[room.ID]
		summary.preview = byRowID[room.PreviewEventRowID]
		if summary.preview != nil {
			for key, name := range names[room.ID] {
				summary.names[key] = name
			}
		}
	}
	return result, nil
}

// syncedChatSummaries maps the rooms in upserted to sidebar chats. Sync can
// touch many rooms at once, so membership, account data and previews load in
// batches instead of per room.
func (s *Dispatcher) syncedChatSummaries(complete *jsoncmd.SyncComplete, upserted map[id.RoomID]bool) map[string]*wire.Chat {
	result := make(map[string]*wire.Chat)
	ctx := context.Background()
	lookup, err := s.buildAccountLookup(ctx)
	if err != nil {
		return result
	}
	rooms := make([]*database.Room, 0, len(complete.Rooms))
	for roomID, syncRoom := range complete.Rooms {
		if syncRoom == nil || !upserted[roomID] {
			continue
		}
		room := syncRoom.Meta
		if room == nil {
			room, _ = s.rt.Client().DB.Room.Get(ctx, roomID)
		}
		if room != nil {
			rooms = append(rooms, room)
		}
	}
	for chunk := range slices.Chunk(rooms, 64) {
		ids := roomIDs(chunk)
		states, err := s.loadRoomAccountDataStates(ctx, ids...)
		if err != nil {
			continue
		}
		reads, _ := s.loadLastReadSortKeys(ctx, ids...)
		summaries, err := s.loadChatSummaries(ctx, chunk, chatPreviewParticipants, lookup)
		if err != nil {
			continue
		}
		for _, room := range chunk {
			chat := s.mapRoomToChat(room, summaries[room.ID], lookup, states[room.ID], reads[room.ID])
			result[string(room.ID)] = &chat
		}
	}
	return result
}
