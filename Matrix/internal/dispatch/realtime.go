package dispatch

import (
	"context"
	"errors"
	"slices"
	"strings"
	"sync"
	"sync/atomic"

	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
	"maunium.net/go/mautrix/id"
)

const realtimeEventQueueSize = 512

// Payload types the app's realtime stream carries.
const (
	realtimeTypeChatUpserted    = "chat.upserted"
	realtimeTypeChatDeleted     = "chat.deleted"
	realtimeTypeMessageUpserted = "message.upserted"
	realtimeTypeReceiptUpdated  = "receipt.updated"
	realtimeTypeTypingUpdated   = "typing.updated"

	realtimeSignalReady                  = "ready"
	realtimeSignalResyncRequired         = "resync.required"
	realtimeSignalPushPreferencesChanged = "push.preferences.changed"
)

// realtimeChange is one change sent to the app. Seq increases by one per
// change, so the app can tell when one was dropped.
type realtimeChange[Entry any] struct {
	Type    string  `json:"type"`
	Seq     int     `json:"seq"`
	ChatID  string  `json:"chatID"`
	Entries []Entry `json:"entries,omitempty"`
}

// realtimeSignal shares the stream without carrying entries or a sequence.
type realtimeSignal struct {
	Type string `json:"type"`
}

// eventHub turns sync results into changes for the app's one realtime
// connection. Sync never blocks on it: events queue, and an overflow asks the
// app to reload from the database instead.
type eventHub struct {
	dispatcher *Dispatcher
	eventQueue chan any
	overflowed atomic.Bool

	mu sync.Mutex
	// connectionID identifies the open connection, so a stale handle can't
	// subscribe or close its replacement.
	connectionID uint64
	send         func(payload any)
	seq          int
	// No changes are sent until the app first subscribes.
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
		switch evt := evt.(type) {
		case *jsoncmd.Typing:
			h.processTyping(evt)
		case *jsoncmd.SyncComplete:
			if evt != nil {
				h.processSyncComplete(evt)
			}
		case *jsoncmd.EventsDecrypted:
			cli := h.dispatcher.rt.Client()
			if evt == nil || cli == nil {
				continue
			}
			room, err := cli.DB.Room.Get(context.Background(), evt.RoomID)
			if err == nil && room != nil {
				h.processSyncComplete(&jsoncmd.SyncComplete{Rooms: map[id.RoomID]*jsoncmd.SyncRoom{
					evt.RoomID: {Meta: room, Events: evt.Events},
				}})
			}
		}
		if h.overflowed.Swap(false) {
			h.signal(realtimeSignalResyncRequired)
		}
	}
}

// OpenRealtime makes connectionID the app's realtime connection, replacing
// any earlier one.
func (s *Dispatcher) OpenRealtime(connectionID uint64, send func(payload any)) {
	h := s.events
	h.mu.Lock()
	defer h.mu.Unlock()
	h.connectionID, h.send, h.seq = connectionID, send, 0
	h.subscribed, h.messageChatIDs = false, nil
	send(realtimeSignal{Type: realtimeSignalReady})
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

func sendChange[Entry any](h *eventHub, kind, chatID string, entries []Entry) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.send == nil {
		return
	}
	h.seq++
	h.send(realtimeChange[Entry]{Type: kind, Seq: h.seq, ChatID: chatID, Entries: entries})
}
