package dispatch

import (
	"context"
	"encoding/json"
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
	if rules := syncComplete.AccountData[event.AccountDataPushRules]; rules != nil && h.pushRulesChanged(rules.Content) {
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
	// Recorded even while the app isn't watching, so the next comparison is
	// against what the database actually held.
	metaChanged := h.recordRoomMeta(syncComplete)
	// Logout briefly leaves no client, then one with no account.
	dispatcher := h.dispatcher
	dispatcher.observeThreadActivity(syncComplete)
	cli := dispatcher.rt.Client()
	if cli == nil || cli.Account == nil || !h.isWatching("", false) {
		return
	}
	changes := syncChanges(syncComplete, cli.Account.UserID, metaChanged)
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

// recordRoomMeta remembers each synced room's metadata and returns the rooms
// whose metadata differs from the last seen. The SDK attaches metadata to
// every room in a sync, even when only someone else's read receipt arrived,
// so its presence alone says nothing changed.
func (h *eventHub) recordRoomMeta(syncComplete *jsoncmd.SyncComplete) map[id.RoomID]bool {
	changed := make(map[id.RoomID]bool)
	for roomID, roomSync := range syncComplete.Rooms {
		if roomSync == nil || roomSync.Meta == nil {
			continue
		}
		meta := *roomSync.Meta
		// Back-pagination moves the batch token without changing the chat.
		meta.PrevBatch = ""
		raw, err := json.Marshal(meta)
		if err != nil {
			changed[roomID] = true
			delete(h.roomMeta, roomID)
			continue
		}
		if h.roomMeta[roomID] != string(raw) {
			changed[roomID] = true
			h.roomMeta[roomID] = string(raw)
		}
	}
	for _, roomID := range syncComplete.LeftRooms {
		delete(h.roomMeta, roomID)
	}
	return changed
}

// syncChanges lists the chats a sync result deleted, changed or added
// messages to, and the rooms with new receipts. metaChanged holds the rooms
// whose metadata actually changed.
func syncChanges(syncComplete *jsoncmd.SyncComplete, self id.UserID, metaChanged map[id.RoomID]bool) []syncChange {
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

		chatTouched := metaChanged[roomID] || len(roomSync.State) > 0 || len(roomSync.AccountData) > 0 || len(roomSync.Timeline) > 0
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
				// A reply changes its thread root's summary.
				if root := threadRootOf(evt); root != "" {
					messageIDs[string(root)] = struct{}{}
				}
			case evtType == event.BeeperMessageStatus.Type:
				// A bridge's delivery report changes the message it reports on.
				if evt.RelatesTo != "" {
					messageIDs[string(evt.RelatesTo)] = struct{}{}
				}
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
// order given, skipping any that don't map to a message. The roots of thread
// replies among them follow, since a reply, its edit or its deletion changes
// the root's summary.
func (s *Dispatcher) loadMessagesByID(chatID string, messageIDs []string) ([]wire.Message, error) {
	ctx := context.Background()
	roomID := id.RoomID(chatID)

	events, err := s.loadRoomEventsByID(ctx, roomID, messageIDs)
	if err != nil || len(events) == 0 {
		return nil, err
	}
	requested := make(map[string]bool, len(messageIDs))
	for _, messageID := range messageIDs {
		requested[messageID] = true
	}
	var roots []string
	for _, evt := range events {
		if root := string(threadRootOf(evt)); root != "" && !requested[root] && !slices.Contains(roots, root) {
			roots = append(roots, root)
		}
	}
	if len(roots) > 0 {
		rootEvents, err := s.loadRoomEventsByID(ctx, roomID, roots)
		if err != nil {
			return nil, err
		}
		events = append(events, rootEvents...)
	}
	messages, err := s.mapEvents(ctx, roomID, events)
	if err != nil {
		return nil, err
	}
	byID := make(map[string]wire.Message, len(messages))
	for _, message := range messages {
		message.TransactionID = strings.TrimSpace(message.TransactionID)
		byID[message.ID] = message
	}
	output := make([]wire.Message, 0, len(byID))
	for _, messageID := range append(slices.Clone(messageIDs), roots...) {
		if entry, ok := byID[messageID]; ok {
			output = append(output, entry)
		}
	}
	return output, nil
}

// loadRoomEventsByID reads the room's events with these IDs, in no order.
func (s *Dispatcher) loadRoomEventsByID(ctx context.Context, roomID id.RoomID, messageIDs []string) ([]*database.Event, error) {
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
	return s.rt.Client().DB.Event.GetByRowIDs(ctx, rowIDs...)
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
