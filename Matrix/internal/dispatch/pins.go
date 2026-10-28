package dispatch

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

// Pins use the standard favorite tag, shared with other Matrix/Beeper clients.
// Tag endpoints change only this tag, preserving Low Priority and custom tags.
func (s *Dispatcher) pinChat(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID string `json:"chatID"`
		Pinned *bool  `json:"pinned"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID, err := required(req.ChatID, "chatID")
	if err != nil {
		return nil, err
	}
	if req.Pinned == nil {
		return nil, errors.New("pinned is required")
	}
	cli := s.rt.Client()
	roomID := id.RoomID(chatID)
	// Keep unknown tag metadata intact in the local cache too.
	var tags struct {
		Tags map[event.RoomTag]json.RawMessage `json:"tags"`
	}
	if err = cli.Client.GetTagsWithCustomData(ctx, roomID, &tags); err != nil {
		return nil, fmt.Errorf("failed to read chat tags: %w", err)
	}
	if tags.Tags == nil {
		tags.Tags = make(map[event.RoomTag]json.RawMessage)
	}
	if *req.Pinned {
		if _, exists := tags.Tags[event.RoomTagFavourite]; !exists {
			states, err := s.loadRoomAccountDataStates(ctx)
			if err != nil {
				return nil, err
			}
			// Append without changing any existing pin's order.
			lastOrder := 0.0
			for _, state := range states {
				if state.IsPinned {
					order := 0.5
					if state.PinOrder != nil {
						order = *state.PinOrder
					}
					lastOrder = max(lastOrder, order)
				}
			}
			metadata := map[string]float64{"order": (lastOrder + 1) / 2}
			if err = cli.Client.AddTagWithCustomData(ctx, roomID, event.RoomTagFavourite, metadata); err != nil {
				return nil, fmt.Errorf("failed to pin chat: %w", err)
			}
			tags.Tags[event.RoomTagFavourite], _ = json.Marshal(metadata)
		}
	} else {
		if err = cli.Client.RemoveTag(ctx, roomID, event.RoomTagFavourite); err != nil && !errors.Is(err, mautrix.MNotFound) {
			return nil, fmt.Errorf("failed to unpin chat: %w", err)
		}
		delete(tags.Tags, event.RoomTagFavourite)
	}
	s.cacheRoomAccountData(ctx, roomID, event.AccountDataRoomTags, tags)
	return wire.Success, nil
}

// Load every pin independently of the chronological list's page window.
func (s *Dispatcher) loadPinnedChats(ctx context.Context, req chatListInput, lookup *accountLookup) ([]wire.Chat, error) {
	cli := s.rt.Client()
	rows, err := cli.DB.Query(ctx, roomSelectBaseQuery+`
		WHERE room_type<>'m.space' AND room_id IN (
			SELECT room_id FROM room_account_data
			WHERE user_id=? AND type='m.tag'
			AND json_type(content, '$.tags."m.favourite"')='object'
		)`, cli.Account.UserID)
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
	if err != nil || len(rooms) == 0 {
		return nil, err
	}
	states, err := s.loadRoomAccountDataStates(ctx, roomIDs(rooms)...)
	if err != nil {
		return nil, err
	}
	rooms = slices.DeleteFunc(rooms, func(room *database.Room) bool {
		return !roomMatchesInbox(room, states[room.ID], strings.TrimSpace(req.Inbox))
	})
	if len(rooms) == 0 {
		return nil, nil
	}
	summaries, err := s.loadChatSummaries(ctx, rooms, chatPreviewParticipants, lookup)
	if err != nil {
		return nil, err
	}
	reads, _ := s.loadLastReadSortKeys(ctx, roomIDs(rooms)...)
	pins := make([]wire.Chat, 0, len(rooms))
	for _, room := range rooms {
		if len(req.AccountIDs) > 0 && !slices.Contains(req.AccountIDs, lookup.roomAccounts[room.ID]) {
			continue
		}
		pins = append(pins, s.mapRoomToChat(room, summaries[room.ID], lookup, states[room.ID], reads[room.ID]))
	}
	return pins, nil
}
