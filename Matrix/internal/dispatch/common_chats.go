package dispatch

import (
	"context"
	"encoding/json"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

const commonChatsLimit = 50

// listCommonChats returns the group chats the user shares with a participant
// on the source chat's account, most recently active first. Like
// findDirectChat, it reads only local membership. The list shows only each
// group's name, avatar and size, so the chats carry no preview, read state or
// settings; the app fetches the full chat to open one.
func (s *Dispatcher) listCommonChats(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ParticipantID string `json:"participantID"`
		SourceChatID  string `json:"sourceChatID"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	participantID, err := required(req.ParticipantID, "participantID")
	if err != nil {
		return nil, err
	}
	sourceChatID, err := required(req.SourceChatID, "sourceChatID")
	if err != nil {
		return nil, err
	}
	cli := s.rt.Client()
	items := make([]wire.Chat, 0)
	if participantID == string(cli.Account.UserID) {
		return items, nil
	}
	lookup, err := s.buildAccountLookup(ctx)
	if err != nil {
		return nil, err
	}
	source, err := s.chatRoom(ctx, id.RoomID(sourceChatID))
	if err != nil {
		return nil, err
	}
	// Summaries infer each room's account into the lookup.
	if _, err = s.loadChatMemberSummaries(ctx, []*database.Room{source}, chatPreviewParticipants, lookup); err != nil {
		return nil, err
	}
	sourceAccount := lookup.roomAccounts[source.ID]

	// Both memberships are filtered in SQL, so only shared rooms are summarized.
	query := roomSelectBaseQuery + `WHERE room_type<>'m.space' AND room_id<>?
		AND EXISTS (
			SELECT 1 FROM current_state cs JOIN event e ON e.rowid=cs.event_rowid
			WHERE cs.room_id=room.room_id AND cs.event_type='m.room.member' AND cs.state_key=?
			AND COALESCE(NULLIF(cs.membership,''),json_extract(e.content,'$.membership'))='join'
		)
		AND EXISTS (
			SELECT 1 FROM current_state cs WHERE cs.room_id=room.room_id
			AND cs.event_type='m.room.member' AND cs.state_key=? AND cs.membership='join'
		) ORDER BY sorting_timestamp DESC,room_id ASC`
	rows, err := cli.DB.Query(ctx, query, sourceChatID, participantID, cli.Account.UserID)
	if err != nil {
		return nil, err
	}
	var rooms []*database.Room
	for rows.Next() {
		room := &database.Room{}
		if _, err = room.Scan(rows); err != nil {
			rows.Close()
			return nil, err
		}
		// A DM user ID marks a direct chat; other DMs need their summary.
		isMarkedDirect := room.DMUserID != nil && *room.DMUserID != ""
		if !isMarkedDirect {
			rooms = append(rooms, room)
		}
		// Enough candidates for a full list, even after other accounts' rooms
		// and unmarked DMs are dropped.
		if len(rooms) == 2*commonChatsLimit {
			break
		}
	}
	err = rows.Err()
	rows.Close()
	if err != nil || len(rooms) == 0 {
		return items, err
	}
	summaries, err := s.loadChatMemberSummaries(ctx, rooms, chatPreviewParticipants, lookup)
	if err != nil {
		return nil, err
	}
	var groups []*database.Room
	for _, room := range rooms {
		if lookup.roomAccounts[room.ID] == sourceAccount && !isDirectChat(room, summaries[room.ID]) {
			groups = append(groups, room)
		}
		if len(groups) == commonChatsLimit {
			break
		}
	}
	for _, room := range groups {
		items = append(items, s.mapRoomToChat(room, summaries[room.ID], lookup, roomAccountDataState{}, ""))
	}
	return items, nil
}
