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
// membership, account-data and preview queries separately for every room.
func (h *eventHub) hydrateChatSummaries(complete *jsoncmd.SyncComplete, duplicates map[string]bool) map[string]*compat.Chat {
	result := make(map[string]*compat.Chat)
	ctx := context.Background()
	lookup, err := h.dispatcher.buildAccountLookup(ctx)
	if err != nil {
		return result
	}
	rooms := make([]*database.Room, 0, len(complete.Rooms))
	for roomID, syncRoom := range complete.Rooms {
		if syncRoom == nil || duplicates[string(roomID)] || len(h.subscribedTargets(string(roomID), false)) == 0 {
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
		summaries, err := h.dispatcher.loadChatSummaries(ctx, chunk, chatPreviewParticipants, lookup, true)
		if err != nil {
			continue
		}
		batchCtx := context.WithValue(ctx, chatSummaryKey{}, summaries)
		for _, room := range chunk {
			chat, err := h.dispatcher.mapRoomToChat(batchCtx, room, lookup, chatPreviewParticipants, true, states[room.ID], reads[room.ID])
			if err == nil {
				result[string(room.ID)] = &chat
			}
		}
	}
	return result
}
