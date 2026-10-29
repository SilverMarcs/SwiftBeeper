package dispatch

import (
	"context"
	"encoding/json"
	"errors"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"maunium.net/go/mautrix/id"
)

// findDirectChat resolves an existing DM locally, using the exact Matrix user
// ID and the source room's account. It never creates a room or contacts a bridge.
func (s *Dispatcher) findDirectChat(ctx context.Context, input json.RawMessage) (any, error) {
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
	if participantID == string(cli.Account.UserID) {
		return nil, errors.New("Choose another participant to message")
	}
	source, err := cli.DB.Room.Get(ctx, id.RoomID(sourceChatID))
	if err != nil {
		return nil, err
	}
	if source == nil {
		return nil, errors.New("Source chat not found")
	}
	lookup, err := s.buildAccountLookup(ctx)
	if err != nil {
		return nil, err
	}
	if _, err = s.loadChatSummaries(ctx, []*database.Room{source}, chatPreviewParticipants, lookup); err != nil {
		return nil, err
	}

	// Filter by membership and DM hints before summarizing, so a participant's
	// large groups are not loaded just to find their one-to-one conversation.
	query := roomSelectBaseQuery + `WHERE room_type<>'m.space' AND room_id<>?
		AND EXISTS (
			SELECT 1 FROM current_state cs JOIN event e ON e.rowid=cs.event_rowid
			WHERE cs.room_id=room.room_id AND cs.event_type='m.room.member' AND cs.state_key=?
			AND COALESCE(NULLIF(cs.membership,''),json_extract(e.content,'$.membership')) IN ('join','invite')
		)
		AND EXISTS (
			SELECT 1 FROM current_state cs WHERE cs.room_id=room.room_id
			AND cs.event_type='m.room.member' AND cs.state_key=? AND cs.membership='join'
		)
		AND (dm_user_id=? OR (COALESCE(dm_user_id,'')='' AND EXISTS (
			SELECT 1 FROM current_state cs JOIN event e ON e.rowid=cs.event_rowid
			WHERE cs.room_id=room.room_id AND cs.event_type='m.room.member'
			AND json_extract(e.content,'$.is_direct')=1
			AND COALESCE(NULLIF(cs.membership,''),json_extract(e.content,'$.membership')) IN ('join','invite')
		))) ORDER BY sorting_timestamp DESC,room_id ASC`
	rows, err := cli.DB.Query(ctx, query, sourceChatID, participantID, cli.Account.UserID, participantID)
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
		rooms = append(rooms, room)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, err
	}
	summaries, err := s.loadChatSummaries(ctx, rooms, chatPreviewParticipants, lookup)
	if err != nil {
		return nil, err
	}
	for _, room := range rooms {
		if !isDirectChat(room, summaries[room.ID]) || lookup.roomAccounts[room.ID] != lookup.roomAccounts[source.ID] {
			continue
		}
		states, err := s.loadRoomAccountDataStates(ctx, room.ID)
		if err != nil {
			return nil, err
		}
		reads, _ := s.loadLastReadSortKeys(ctx, room.ID)
		return s.mapRoomToChat(room, summaries[room.ID], lookup, states[room.ID], reads[room.ID]), nil
	}
	return nil, nil
}
