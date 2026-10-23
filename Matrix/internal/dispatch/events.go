package dispatch

import (
	"context"
	"errors"
	"slices"
	"sort"
	"strings"
	"sync"
	"sync/atomic"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/compat"
)

const (
	realtimeEventQueueSize            = 512
	realtimeDomainTypeChatUpserted    = "chat.upserted"
	realtimeDomainTypeChatDeleted     = "chat.deleted"
	realtimeDomainTypeMessageUpserted = "message.upserted"
	realtimeDomainTypeReceiptUpdated  = "receipt.updated"
)

// realtimeDomainMessage is one change sent to the app. Seq increases by one
// per message, so the app can tell when one was dropped.
type realtimeDomainMessage[Entry any] struct {
	Type    string  `json:"type"`
	Seq     int     `json:"seq"`
	ChatID  string  `json:"chatID"`
	Entries []Entry `json:"entries,omitempty"`
}

// Signals share the same event stream without carrying domain entries.
type realtimeSignal struct {
	Type string `json:"type"`
}

type domainEvent struct {
	Type   string
	ChatID string
	IDs    []string
}

type receiptUpdate struct {
	ChatID                 string `json:"chatID"`
	LastReadByOtherSortKey string `json:"lastReadByOtherSortKey"`
}

type realtimeSender func(payload any)

// eventHub turns sync results into changes for the app's one realtime
// connection. Sync never blocks on it: events queue, and an overflow asks the
// app to reload from the database instead.
type eventHub struct {
	dispatcher *Dispatcher
	eventQueue chan any
	overflowed atomic.Bool

	mu             sync.Mutex
	connectionID   uint64
	send           realtimeSender
	seq            int
	subscribed     bool
	messageChatIDs []string
}

func newEventHub(dispatcher *Dispatcher) *eventHub {
	h := &eventHub{dispatcher: dispatcher, eventQueue: make(chan any, realtimeEventQueueSize)}
	go h.run()
	return h
}

func (h *eventHub) enqueue(evt any) {
	select {
	case h.eventQueue <- evt:
	default:
		h.overflowed.Store(true)
	}
}

func (h *eventHub) run() {
	for evt := range h.eventQueue {
		switch complete := evt.(type) {
		case *jsoncmd.SyncComplete:
			if complete != nil {
				h.processSyncComplete(complete)
			}
		case *jsoncmd.EventsDecrypted:
			cli := h.dispatcher.rt.Client()
			if complete == nil || cli == nil {
				continue
			}
			room, err := cli.DB.Room.Get(context.Background(), complete.RoomID)
			if err == nil && room != nil {
				h.processSyncComplete(&jsoncmd.SyncComplete{Rooms: map[id.RoomID]*jsoncmd.SyncRoom{
					complete.RoomID: {Meta: room, Events: complete.Events},
				}})
			}
		}
		if h.overflowed.Swap(false) {
			h.signal("resync.required")
		}
	}
}

// OpenRealtime makes connectionID the app's realtime connection, replacing
// any earlier one.
func (s *Dispatcher) OpenRealtime(connectionID uint64, send realtimeSender) {
	h := s.events
	h.mu.Lock()
	defer h.mu.Unlock()
	h.connectionID, h.send, h.seq = connectionID, send, 0
	h.subscribed, h.messageChatIDs = false, nil
	send(realtimeSignal{Type: "ready"})
}

// SubscribeRealtime selects which chats get message updates. Sidebar updates
// always cover every chat.
func (s *Dispatcher) SubscribeRealtime(connectionID uint64, messageChatIDs []string) error {
	for _, roomID := range messageChatIDs {
		if strings.TrimSpace(roomID) == "" || roomID == "*" {
			return errors.New("message subscriptions require explicit room IDs")
		}
	}
	h := s.events
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.connectionID != connectionID || h.send == nil {
		return errors.New("realtime connection is closed")
	}
	h.subscribed, h.messageChatIDs = true, slices.Clone(messageChatIDs)
	return nil
}

func (s *Dispatcher) CloseRealtime(connectionID uint64) {
	h := s.events
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.connectionID == connectionID {
		h.connectionID, h.send = 0, nil
	}
}

// isWatching reports whether the app wants this chat's changes. Message and
// receipt details only go to chats the app subscribed to.
func (h *eventHub) isWatching(chatID string, detailed bool) bool {
	h.mu.Lock()
	defer h.mu.Unlock()
	return h.send != nil && h.subscribed && (!detailed || slices.Contains(h.messageChatIDs, chatID))
}

func (h *eventHub) signal(kind string) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.send != nil {
		h.send(realtimeSignal{Type: kind})
	}
}

func sendDomainEvent[Entry any](h *eventHub, domainEvent domainEvent, entries []Entry) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.send == nil {
		return
	}
	h.seq++
	h.send(realtimeDomainMessage[Entry]{Type: domainEvent.Type, Seq: h.seq, ChatID: domainEvent.ChatID, Entries: entries})
}

func (h *eventHub) processSyncComplete(syncComplete *jsoncmd.SyncComplete) {
	for _, room := range syncComplete.Rooms {
		if room != nil && (room.AccountData[event.AccountDataBeeperMute] != nil ||
			room.AccountData[event.AccountDataRoomTags] != nil ||
			room.AccountData[event.Type{Type: "com.beeper.inbox.done", Class: event.AccountDataEventType}] != nil ||
			room.AccountData[event.Type{Type: "m.marked_unread", Class: event.AccountDataEventType}] != nil) {
			h.signal("push.preferences.changed")
			break
		}
	}
	// Logout briefly leaves no client, then one with no account.
	cli := h.dispatcher.rt.Client()
	if cli == nil || cli.Account == nil || !h.isWatching("", false) {
		return
	}
	domainEvents := mapSyncCompleteToDomainEvents(syncComplete, cli.Account.UserID)
	upserted := make(map[id.RoomID]bool)
	for _, domainEvent := range domainEvents {
		if domainEvent.Type == realtimeDomainTypeChatUpserted {
			upserted[id.RoomID(domainEvent.ChatID)] = true
		}
	}
	summaries := h.hydrateChatSummaries(syncComplete, upserted)
	for _, domainEvent := range domainEvents {
		detailed := domainEvent.Type == realtimeDomainTypeMessageUpserted || domainEvent.Type == realtimeDomainTypeReceiptUpdated
		if !h.isWatching(domainEvent.ChatID, detailed) {
			continue
		}
		switch domainEvent.Type {
		case realtimeDomainTypeMessageUpserted:
			entries, err := h.dispatcher.hydrateMessageUpdates(domainEvent.ChatID, domainEvent.IDs)
			// Redacted edits, undecryptable events and state events map to no
			// message; sending nothing keeps the app from reloading for them.
			if err != nil || len(entries) == 0 {
				continue
			}
			sendDomainEvent(h, domainEvent, entries)
		case realtimeDomainTypeReceiptUpdated:
			if key := h.dispatcher.loadLastReadByOther(context.Background(), id.RoomID(domainEvent.ChatID)); key != "" {
				sendDomainEvent(h, domainEvent, []receiptUpdate{{ChatID: domainEvent.ChatID, LastReadByOtherSortKey: key}})
			}
		case realtimeDomainTypeChatUpserted:
			// A missing summary sends no entries, which tells the app to reload.
			var entries []compat.Chat
			if summary := summaries[domainEvent.ChatID]; summary != nil {
				entries = []compat.Chat{*summary}
			}
			sendDomainEvent(h, domainEvent, entries)
		default:
			sendDomainEvent[struct{}](h, domainEvent, nil)
		}
	}
}

// hydrateMessageUpdates maps the given message IDs to complete messages,
// in the order given.
func (s *Dispatcher) hydrateMessageUpdates(chatID string, messageIDs []string) ([]compat.Message, error) {
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
	rows, err := cli.DB.Query(ctx, `SELECT rowid FROM event WHERE room_id=? AND event_id IN (`+sqlSlots(len(args)-1)+`)`, args...)
	if err != nil {
		return nil, err
	}
	var rowIDs []database.EventRowID
	for rows.Next() {
		var rowID database.EventRowID
		if err = rows.Scan(&rowID); err != nil {
			rows.Close()
			return nil, err
		}
		rowIDs = append(rowIDs, rowID)
	}
	err = rows.Err()
	rows.Close()
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

	byID := make(map[string]compat.Message, len(events))
	for _, evt := range events {
		if message, mapErr := s.mapEventToMessage(evt, names, reactions); mapErr == nil {
			message.TransactionID = strings.TrimSpace(evt.TransactionID)
			byID[message.ID] = message
		}
	}
	output := make([]compat.Message, 0, len(byID))
	for _, messageID := range messageIDs {
		if entry, ok := byID[messageID]; ok {
			output = append(output, entry)
		}
	}
	return output, nil
}

func mapSyncCompleteToDomainEvents(syncComplete *jsoncmd.SyncComplete, self id.UserID) []domainEvent {
	output := make([]domainEvent, 0, len(syncComplete.Rooms)*2+len(syncComplete.LeftRooms))

	for _, leftRoom := range syncComplete.LeftRooms {
		if chatID := strings.TrimSpace(leftRoom.String()); chatID != "" {
			output = append(output, domainEvent{Type: realtimeDomainTypeChatDeleted, ChatID: chatID})
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
			output = append(output, domainEvent{Type: realtimeDomainTypeReceiptUpdated, ChatID: chatID})
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
			output = append(output, domainEvent{Type: realtimeDomainTypeChatUpserted, ChatID: chatID})
		}
		if len(messageIDs) > 0 {
			output = append(output, domainEvent{Type: realtimeDomainTypeMessageUpserted, ChatID: chatID, IDs: sortedKeys(messageIDs)})
		}
	}
	return output
}

func sortedKeys(values map[string]struct{}) []string {
	output := make([]string, 0, len(values))
	for key := range values {
		if strings.TrimSpace(key) != "" {
			output = append(output, key)
		}
	}
	sort.Strings(output)
	return output
}
