package dispatch

import (
	"context"
	"slices"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/compat"
)

// Sync can touch many rooms at once. Batch sidebar hydration instead of issuing
// membership, account-data and preview queries separately for every room. Only
// rooms in upserted are summarized.
func (h *eventHub) hydrateChatSummaries(complete *jsoncmd.SyncComplete, upserted map[id.RoomID]bool) map[string]*compat.Chat {
	result := make(map[string]*compat.Chat)
	ctx := context.Background()
	lookup, err := h.dispatcher.buildAccountLookup(ctx)
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
			room, _ = h.dispatcher.rt.Client().DB.Room.Get(ctx, roomID)
		}
		if room != nil {
			rooms = append(rooms, room)
		}
	}
	for chunk := range slices.Chunk(rooms, 64) {
		ids := make([]id.RoomID, len(chunk))
		for i, room := range chunk {
			ids[i] = room.ID
		}
		states, err := h.dispatcher.loadRoomAccountDataStates(ctx, ids...)
		if err != nil {
			continue
		}
		reads, _ := h.dispatcher.loadLastReadSortKeys(ctx, ids...)
		summaries, err := h.dispatcher.loadChatSummaries(ctx, chunk, chatPreviewParticipants, lookup)
		if err != nil {
			continue
		}
		for _, room := range chunk {
			chat := h.dispatcher.mapRoomToChat(room, summaries[room.ID], lookup, states[room.ID], reads[room.ID])
			result[string(room.ID)] = &chat
		}
	}
	return result
}
