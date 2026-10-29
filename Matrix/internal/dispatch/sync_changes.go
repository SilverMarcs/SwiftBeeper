package dispatch

import (
	"context"
	"slices"
	"sort"
	"strings"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

// syncChange is one chat-level change found in a sync result, before its
// entries are loaded.
type syncChange struct {
	Type   string
	ChatID string
	// Message IDs, for message.upserted.
	IDs []string
}

type receiptUpdate struct {
	ChatID                 string `json:"chatID"`
	LastReadByOtherSortKey string `json:"lastReadByOtherSortKey"`
}

func (h *eventHub) processSyncComplete(syncComplete *jsoncmd.SyncComplete) {
	if syncComplete.AccountData[event.AccountDataPushRules] != nil {
		// A rule can change without any room events, including in another client.
		h.signal(realtimeSignalPushPreferencesChanged)
		h.signal(realtimeSignalResyncRequired)
	}
	for _, room := range syncComplete.Rooms {
		if room != nil && (room.AccountData[event.AccountDataBeeperMute] != nil ||
			room.AccountData[event.AccountDataRoomTags] != nil ||
			room.AccountData[accountDataInboxDone] != nil ||
			room.AccountData[accountDataMarkedUnread] != nil) {
			h.signal(realtimeSignalPushPreferencesChanged)
			break
		}
	}
	// Logout briefly leaves no client, then one with no account.
	dispatcher := h.dispatcher
	cli := dispatcher.rt.Client()
	if cli == nil || cli.Account == nil || !h.isWatching("", false) {
		return
	}
	changes := syncChanges(syncComplete, cli.Account.UserID)
	upserted := make(map[id.RoomID]bool)
	for _, change := range changes {
		if change.Type == realtimeTypeChatUpserted {
			upserted[id.RoomID(change.ChatID)] = true
		}
	}
	summaries := dispatcher.syncedChatSummaries(syncComplete, upserted)
	for _, change := range changes {
		detailed := change.Type == realtimeTypeMessageUpserted || change.Type == realtimeTypeReceiptUpdated
		if !h.isWatching(change.ChatID, detailed) {
			continue
		}
		switch change.Type {
		case realtimeTypeMessageUpserted:
			entries, err := dispatcher.loadMessagesByID(change.ChatID, change.IDs)
			// Redacted edits, undecryptable events and state events map to no
			// message; sending nothing keeps the app from reloading for them.
			if err != nil || len(entries) == 0 {
				continue
			}
			sendChange(h, change.Type, change.ChatID, entries)
		case realtimeTypeReceiptUpdated:
			if key := dispatcher.loadLastReadByOther(context.Background(), id.RoomID(change.ChatID)); key != "" {
				sendChange(h, change.Type, change.ChatID, []receiptUpdate{{ChatID: change.ChatID, LastReadByOtherSortKey: key}})
			}
		case realtimeTypeChatUpserted:
			// A missing summary sends no entries, which tells the app to reload.
			var entries []wire.Chat
			if summary := summaries[change.ChatID]; summary != nil {
				entries = []wire.Chat{*summary}
			}
			sendChange(h, change.Type, change.ChatID, entries)
		default:
			sendChange[struct{}](h, change.Type, change.ChatID, nil)
		}
	}
}

// syncChanges lists the chats a sync result deleted, changed or added
// messages to, and the rooms with new receipts.
func syncChanges(syncComplete *jsoncmd.SyncComplete, self id.UserID) []syncChange {
	output := make([]syncChange, 0, len(syncComplete.Rooms)*2+len(syncComplete.LeftRooms))

	for _, leftRoom := range syncComplete.LeftRooms {
		if chatID := strings.TrimSpace(leftRoom.String()); chatID != "" {
			output = append(output, syncChange{Type: realtimeTypeChatDeleted, ChatID: chatID})
		}
	}

	for roomID, roomSync := range syncComplete.Rooms {
		chatID := strings.TrimSpace(roomID.String())
		if chatID == "" || roomSync == nil {
			continue
		}

		chatTouched := roomSync.Meta != nil || len(roomSync.State) > 0 || len(roomSync.AccountData) > 0 || len(roomSync.Timeline) > 0
		// Redactions update their target in place, so they share the upsert.
		messageIDs := make(map[string]struct{})
		for _, evt := range roomSync.Events {
			if evt == nil {
				continue
			}
			evtType := evt.GetType().Type
			switch {
			case evtType == event.EventRedaction.Type:
				if evt.RelatesTo != "" {
					messageIDs[string(evt.RelatesTo)] = struct{}{}
				}
			case evt.RedactedBy != "":
				messageIDs[string(evt.ID)] = struct{}{}
			case evtType == event.EventMessage.Type || evtType == event.EventSticker.Type || evtType == event.EventReaction.Type:
				chatTouched = true
				// Reactions and edits change the message they point at.
				targetID := string(evt.ID)
				if (evtType == event.EventReaction.Type || evt.RelationType == event.RelReplace) && evt.RelatesTo != "" {
					targetID = string(evt.RelatesTo)
				}
				messageIDs[targetID] = struct{}{}
			case evtType == event.StateMember.Type ||
				evtType == event.StateRoomName.Type ||
				evtType == event.StateRoomAvatar.Type ||
				evtType == event.StateTopic.Type:
				chatTouched = true
			}
		}

		if len(roomSync.Receipts) > 0 {
			output = append(output, syncChange{Type: realtimeTypeReceiptUpdated, ChatID: chatID})
			// Only the user's own receipt changes the chat (its read position).
			for _, receipts := range roomSync.Receipts {
				for _, receipt := range receipts {
					if receipt != nil && receipt.UserID == self {
						chatTouched = true
					}
				}
			}
		}
		if chatTouched {
			output = append(output, syncChange{Type: realtimeTypeChatUpserted, ChatID: chatID})
		}
		if len(messageIDs) > 0 {
			output = append(output, syncChange{Type: realtimeTypeMessageUpserted, ChatID: chatID, IDs: sortedNonBlankKeys(messageIDs)})
		}
	}
	return output
}

func sortedNonBlankKeys(values map[string]struct{}) []string {
	output := make([]string, 0, len(values))
	for key := range values {
		if strings.TrimSpace(key) != "" {
			output = append(output, key)
		}
	}
	sort.Strings(output)
	return output
}

// loadMessagesByID maps the given message IDs to complete messages, in the
// order given, skipping any that don't map to a message.
func (s *Dispatcher) loadMessagesByID(chatID string, messageIDs []string) ([]wire.Message, error) {
	ctx := context.Background()
	cli := s.rt.Client()
	roomID := id.RoomID(chatID)

	args := []any{roomID}
	for _, messageID := range slices.Compact(slices.Sorted(slices.Values(messageIDs))) {
		if messageID != "" {
			args = append(args, messageID)
		}
	}
	if len(args) == 1 {
		return nil, nil
	}
	rowIDs, err := s.queryEventRowIDs(ctx, `SELECT rowid FROM event WHERE room_id=? AND event_id IN (`+sqlSlots(len(args)-1)+`)`, args...)
	if err != nil || len(rowIDs) == 0 {
		return nil, err
	}
	events, err := cli.DB.Event.GetByRowIDs(ctx, rowIDs...)
	if err != nil {
		return nil, err
	}
	if err = s.populateTimelinePositions(ctx, events); err != nil {
		return nil, err
	}
	if err = s.populateLastEditRefs(ctx, events); err != nil {
		return nil, err
	}
	names := s.loadNamesForEvents(ctx, events)[roomID]
	reactions, _ := s.loadReactionMap(ctx, roomID, events)

	byID := make(map[string]wire.Message, len(events))
	for _, evt := range events {
		if message, err := s.mapEventToMessage(evt, names, reactions); err == nil {
			message.TransactionID = strings.TrimSpace(evt.TransactionID)
			byID[message.ID] = message
		}
	}
	output := make([]wire.Message, 0, len(byID))
	for _, messageID := range messageIDs {
		if entry, ok := byID[messageID]; ok {
			output = append(output, entry)
		}
	}
	return output, nil
}

func (s *Dispatcher) queryEventRowIDs(ctx context.Context, query string, args ...any) ([]database.EventRowID, error) {
	rows, err := s.rt.Client().DB.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var rowIDs []database.EventRowID
	for rows.Next() {
		var rowID database.EventRowID
		if err = rows.Scan(&rowID); err != nil {
			return nil, err
		}
		rowIDs = append(rowIDs, rowID)
	}
	return rowIDs, rows.Err()
}
