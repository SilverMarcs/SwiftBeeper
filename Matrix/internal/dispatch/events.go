package dispatch

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"

	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/compat"
)

const (
	realtimeDuplicateEventDebounce    = 250 * time.Millisecond
	realtimeFingerprintRetention      = 30 * time.Second
	realtimeFingerprintPruneInterval  = 5 * time.Second
	realtimeEventQueueSize            = 512
	realtimeReadyType                 = "ready"
	realtimeDomainTypeChatUpserted    = "chat.upserted"
	realtimeDomainTypeChatDeleted     = "chat.deleted"
	realtimeDomainTypeMessageUpserted = "message.upserted"
	realtimeDomainTypeMessageDeleted  = "message.deleted"
	realtimeDomainTypeReceiptUpdated  = "receipt.updated"
	maxPushParticipants               = 8
)

type realtimeDomainMessage[Entry any] struct {
	Type    string   `json:"type"`
	Seq     int      `json:"seq"`
	TS      int64    `json:"ts"`
	ChatID  string   `json:"chatID"`
	IDs     []string `json:"ids"`
	Entries []Entry  `json:"entries,omitempty"`
}

type domainEvent struct {
	Type   string
	ChatID string
	IDs    []string
}

type eventClientState struct {
	seq            int
	messageChatIDs []string
	subscribed     bool
	writeMu        sync.Mutex
}

type realtimeSender func(any) error

type eventClient struct {
	id    uint64
	state *eventClientState
	send  realtimeSender
}

type RealtimeConnection struct {
	hub    *eventHub
	id     uint64
	closed atomic.Bool
}

// Subscribe selects detailed message updates. Sidebar summaries always cover
// all conversations; the Swift app only needs message bodies for visible rooms.
func (c *RealtimeConnection) Subscribe(messageChatIDs []string) error {
	if c == nil || c.closed.Load() {
		return errors.New("realtime connection is closed")
	}
	for _, roomID := range messageChatIDs {
		if strings.TrimSpace(roomID) == "" || roomID == "*" {
			return errors.New("message subscriptions require explicit room IDs")
		}
	}
	c.hub.setSubscriptions(c.id, messageChatIDs)
	return nil
}

func (c *RealtimeConnection) Close() {
	if c == nil || c.closed.Swap(true) {
		return
	}
	c.hub.unregister(c.id)
}

type eventHub struct {
	dispatcher *Dispatcher

	mu           sync.RWMutex
	clients      map[uint64]*eventClient
	nextClientID uint64

	subscribeMu sync.Mutex
	unsubscribe func()

	eventQueue chan any
	overflowed atomic.Bool

	fingerprintMu        sync.Mutex
	recentFingerprints   map[string]time.Time
	lastFingerprintPrune time.Time
}

func newEventHub(dispatcher *Dispatcher) *eventHub {
	return &eventHub{
		dispatcher:         dispatcher,
		clients:            make(map[uint64]*eventClient),
		eventQueue:         make(chan any, realtimeEventQueueSize),
		recentFingerprints: make(map[string]time.Time),
	}
}

func (h *eventHub) ensureSubscription() {
	h.subscribeMu.Lock()
	defer h.subscribeMu.Unlock()
	if h.unsubscribe != nil {
		return
	}

	h.unsubscribe = h.dispatcher.rt.Subscribe(func(evt any) {
		select {
		case h.eventQueue <- evt:
		default:
			// Do not block sync; reconcile from SQLite after the burst instead.
			h.overflowed.Store(true)
		}
	})
	go h.run()
}

func (h *eventHub) run() {
	for evt := range h.eventQueue {
		switch complete := evt.(type) {
		case *jsoncmd.SyncComplete:
			if complete != nil {
				h.processSyncComplete(complete)
			}
		case *jsoncmd.EventsDecrypted:
			if complete == nil {
				continue
			}
			room, err := h.dispatcher.rt.Client().DB.Room.Get(context.Background(), complete.RoomID)
			if err == nil && room != nil {
				h.processSyncComplete(&jsoncmd.SyncComplete{Rooms: map[id.RoomID]*jsoncmd.SyncRoom{
					complete.RoomID: {Meta: room, Events: complete.Events},
				}})
			}
		}
		if h.overflowed.Swap(false) {
			h.mu.RLock()
			clients := make([]*eventClient, 0, len(h.clients))
			for _, client := range h.clients {
				clients = append(clients, client)
			}
			h.mu.RUnlock()
			for _, client := range clients {
				h.write(client, realtimeSignal{Type: "resync.required"})
			}
		}
	}
}

func (h *eventHub) register(send realtimeSender) uint64 {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.nextClientID++
	id := h.nextClientID
	h.clients[id] = &eventClient{
		id:    id,
		state: &eventClientState{},
		send:  send,
	}
	return id
}

func (h *eventHub) open(send realtimeSender) *RealtimeConnection {
	h.ensureSubscription()
	id := h.register(send)
	client := h.client(id)
	h.write(client, realtimeSignal{Type: realtimeReadyType})
	return &RealtimeConnection{hub: h, id: id}
}

func (s *Dispatcher) OpenRealtime(send realtimeSender) *RealtimeConnection {
	return s.events.open(send)
}

func (h *eventHub) client(id uint64) *eventClient {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return h.clients[id]
}

func (h *eventHub) unregister(id uint64) {
	h.mu.Lock()
	delete(h.clients, id)
	h.mu.Unlock()
}

func (h *eventHub) setSubscriptions(id uint64, messageChatIDs []string) {
	h.mu.Lock()
	if client, ok := h.clients[id]; ok {
		client.state.messageChatIDs = append([]string(nil), messageChatIDs...)
		client.state.subscribed = true
	}
	h.mu.Unlock()
}

func (h *eventHub) processSyncComplete(syncComplete *jsoncmd.SyncComplete) {
	for _, room := range syncComplete.Rooms {
		if room != nil && (room.AccountData[event.AccountDataBeeperMute] != nil ||
			room.AccountData[event.AccountDataRoomTags] != nil ||
			room.AccountData[event.Type{Type: "com.beeper.inbox.done", Class: event.AccountDataEventType}] != nil ||
			room.AccountData[event.Type{Type: "m.marked_unread", Class: event.AccountDataEventType}] != nil) {
			h.notifyNotificationPreferencesChanged()
			break
		}
	}
	now := time.Now().UTC()
	duplicateRooms := make(map[string]bool)
	for roomID, room := range syncComplete.Rooms {
		raw, _ := json.Marshal(room)
		sum := sha256.Sum256(raw)
		duplicateRooms[string(roomID)] = h.dropDuplicate(string(roomID)+"|"+hex.EncodeToString(sum[:]), now)
	}
	domainEvents := mapSyncCompleteToDomainEvents(syncComplete)
	summaries := h.hydrateChatSummaries(syncComplete, duplicateRooms)
	for _, domainEvent := range domainEvents {
		if duplicateRooms[domainEvent.ChatID] {
			continue
		}
		detailed := domainEvent.Type == realtimeDomainTypeMessageUpserted || domainEvent.Type == realtimeDomainTypeMessageDeleted || domainEvent.Type == realtimeDomainTypeReceiptUpdated
		targets := h.subscribedTargets(domainEvent.ChatID, detailed)
		if len(targets) == 0 {
			continue
		}

		switch domainEvent.Type {
		case realtimeDomainTypeMessageUpserted, realtimeDomainTypeMessageDeleted:
			entries, err := h.dispatcher.hydrateMessageUpdates(domainEvent.ChatID, domainEvent.IDs)
			if err != nil || (domainEvent.Type == realtimeDomainTypeMessageUpserted && len(entries) == 0) {
				continue
			}
			broadcastDomainEvent(h, targets, domainEvent, entries, now)
		case realtimeDomainTypeReceiptUpdated:
			receipt, err := h.dispatcher.hydrateReceiptUpdate(domainEvent.ChatID)
			var entries []receiptUpdate
			if err == nil && receipt != nil {
				entries = []receiptUpdate{*receipt}
			}
			broadcastDomainEvent(h, targets, domainEvent, entries, now)
		case realtimeDomainTypeChatUpserted:
			var entries []compat.Chat
			if summary := summaries[domainEvent.ChatID]; summary != nil {
				entries = []compat.Chat{*summary}
			}
			broadcastDomainEvent(h, targets, domainEvent, entries, now)
		default:
			broadcastDomainEvent[struct{}](h, targets, domainEvent, nil, now)
		}
	}
}

// Encode the concrete entry type once at the C bridge. No JSON-to-map round trip.
func broadcastDomainEvent[Entry any](h *eventHub, targets []*eventClient, domainEvent domainEvent, entries []Entry, now time.Time) {
	for _, target := range targets {
		target.state.seq++
		h.write(target, realtimeDomainMessage[Entry]{
			Type: domainEvent.Type, Seq: target.state.seq, TS: now.UnixMilli(),
			ChatID: domainEvent.ChatID, IDs: domainEvent.IDs, Entries: entries,
		})
	}
}

// Signals share the same event stream without carrying domain entries.
type realtimeSignal struct {
	Type string `json:"type"`
}

func (h *eventHub) notifyNotificationPreferencesChanged() {
	h.mu.RLock()
	clients := make([]*eventClient, 0, len(h.clients))
	for _, client := range h.clients {
		clients = append(clients, client)
	}
	h.mu.RUnlock()
	for _, client := range clients {
		h.write(client, realtimeSignal{Type: "push.preferences.changed"})
	}
}

func (h *eventHub) subscribedTargets(chatID string, detailed bool) []*eventClient {
	h.mu.RLock()
	defer h.mu.RUnlock()

	output := make([]*eventClient, 0, len(h.clients))
	for _, client := range h.clients {
		if client == nil || client.state == nil || !client.state.subscribed {
			continue
		}
		if !detailed || isSubscribed(client.state.messageChatIDs, chatID) {
			output = append(output, client)
		}
	}
	return output
}

func (h *eventHub) dropDuplicate(fingerprint string, now time.Time) bool {
	h.fingerprintMu.Lock()
	defer h.fingerprintMu.Unlock()

	previousAt, hasPrevious := h.recentFingerprints[fingerprint]
	h.recentFingerprints[fingerprint] = now
	h.pruneFingerprintsLocked(now)

	return hasPrevious && now.Sub(previousAt) < realtimeDuplicateEventDebounce
}

func (h *eventHub) pruneFingerprintsLocked(now time.Time) {
	if now.Sub(h.lastFingerprintPrune) < realtimeFingerprintPruneInterval {
		return
	}
	h.lastFingerprintPrune = now
	for fingerprint, lastSeen := range h.recentFingerprints {
		if now.Sub(lastSeen) > realtimeFingerprintRetention {
			delete(h.recentFingerprints, fingerprint)
		}
	}
}

func (h *eventHub) write(client *eventClient, payload any) {
	if client == nil || client.state == nil || client.send == nil {
		return
	}

	client.state.writeMu.Lock()
	err := client.send(payload)
	client.state.writeMu.Unlock()
	if err != nil {
		h.unregister(client.id)
	}
}

func (s *Dispatcher) hydrateMessageUpdates(chatID string, messageIDs []string) ([]compat.Message, error) {
	cli := s.rt.Client()
	if cli == nil {
		return nil, nil
	}
	roomID := id.RoomID(chatID)
	room, err := cli.DB.Room.Get(context.Background(), roomID)
	if err != nil || room == nil {
		return nil, nil
	}

	lookup, err := s.buildAccountLookup(context.Background())
	if err != nil {
		return nil, err
	}

	seen := make(map[string]bool, len(messageIDs))
	args := []any{roomID}
	for _, messageID := range messageIDs {
		if messageID != "" && !seen[messageID] {
			seen[messageID] = true
			args = append(args, messageID)
		}
	}
	if len(args) == 1 {
		return nil, nil
	}
	rows, err := cli.DB.Query(context.Background(), `SELECT rowid FROM event WHERE room_id=? AND event_id IN (`+sqlSlots(len(args)-1)+`)`, args...)
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
	if err != nil {
		return nil, err
	}
	events, err := cli.DB.Event.GetByRowIDs(context.Background(), rowIDs...)
	if err != nil {
		return nil, err
	}
	if err = s.populateTimelinePositions(context.Background(), events); err != nil {
		return nil, err
	}
	if _, err = s.loadChatSummaries(context.Background(), []*database.Room{room}, 0, lookup, false); err != nil {
		return nil, err
	}

	if len(events) == 0 {
		return nil, nil
	}
	if err = s.populateLastEditRefs(context.Background(), events); err != nil {
		return nil, err
	}

	memberNames := s.loadNamesForEvents(context.Background(), events)[roomID]
	reactions, _ := s.loadReactionMap(context.Background(), roomID, events)

	byID := make(map[string]compat.Message, len(events))
	for _, evt := range events {
		message, mapErr := s.mapEventToMessage(context.Background(), evt, room, lookup, reactionBundle{
			Names:     memberNames,
			Reactions: reactions,
		})
		if errors.Is(mapErr, errSkipEvent) || mapErr != nil {
			continue
		}
		message.TransactionID = strings.TrimSpace(evt.TransactionID)
		byID[message.ID] = message
	}

	output := make([]compat.Message, 0, len(messageIDs))
	for _, messageID := range messageIDs {
		if entry, ok := byID[messageID]; ok {
			output = append(output, entry)
		}
	}
	return output, nil
}

type receiptUpdate struct {
	ChatID                 string `json:"chatID"`
	LastReadByOtherSortKey string `json:"lastReadByOtherSortKey"`
}

func (s *Dispatcher) hydrateReceiptUpdate(chatID string) (*receiptUpdate, error) {
	otherReceipts, err := s.loadOtherReadReceipts(context.Background(), id.RoomID(chatID))
	if err != nil {
		return nil, err
	}
	maxRead := computeMaxOtherRead(otherReceipts)
	if maxRead == 0 {
		return nil, nil
	}
	return &receiptUpdate{ChatID: chatID, LastReadByOtherSortKey: strconv.FormatInt(maxRead, 10)}, nil
}

func isSubscribed(subscribedChatIDs []string, chatID string) bool {
	if len(subscribedChatIDs) == 0 {
		return false
	}
	for _, subscribed := range subscribedChatIDs {
		if subscribed == chatID {
			return true
		}
	}
	return false
}

func mapSyncCompleteToDomainEvents(syncComplete *jsoncmd.SyncComplete) []domainEvent {
	output := make([]domainEvent, 0, len(syncComplete.Rooms)*2+len(syncComplete.LeftRooms))

	for _, leftRoom := range syncComplete.LeftRooms {
		chatID := strings.TrimSpace(leftRoom.String())
		if chatID == "" {
			continue
		}
		output = append(output, domainEvent{
			Type:   realtimeDomainTypeChatDeleted,
			ChatID: chatID,
			IDs:    []string{chatID},
		})
	}

	for roomID, roomSync := range syncComplete.Rooms {
		chatID := strings.TrimSpace(roomID.String())
		if chatID == "" || roomSync == nil {
			continue
		}

		chatTouched := roomSync.Meta != nil || len(roomSync.State) > 0 || len(roomSync.AccountData) > 0
		if !chatTouched && len(roomSync.Timeline) > 0 {
			chatTouched = true
		}

		messageUpsertIDs := make(map[string]struct{})
		messageDeletedIDs := make(map[string]struct{})

		for _, evt := range roomSync.Events {
			if evt == nil {
				continue
			}
			evtType := evt.GetType().Type

			switch {
			case evtType == event.EventRedaction.Type:
				if evt.RelatesTo != "" {
					messageDeletedIDs[string(evt.RelatesTo)] = struct{}{}
				}
			case evt.RedactedBy != "":
				if evt.ID != "" {
					messageDeletedIDs[string(evt.ID)] = struct{}{}
				}
			case evtType == event.EventMessage.Type || evtType == event.EventSticker.Type ||
				evtType == event.EventReaction.Type || evtType == event.StateMember.Type:
				chatTouched = true
				targetID := string(evt.ID)
				if evtType == event.EventReaction.Type && evt.RelatesTo != "" {
					targetID = string(evt.RelatesTo)
				}
				if evt.RelationType == event.RelReplace && evt.RelatesTo != "" {
					targetID = string(evt.RelatesTo)
				}
				targetID = strings.TrimSpace(targetID)
				if targetID != "" {
					messageUpsertIDs[targetID] = struct{}{}
				}
			case evtType == event.StateMember.Type ||
				evtType == event.StateRoomName.Type ||
				evtType == event.StateRoomAvatar.Type ||
				evtType == event.StateTopic.Type:
				chatTouched = true
			}
		}

		// Emit receipt.updated if new receipts arrived.
		if len(roomSync.Receipts) > 0 {
			output = append(output, domainEvent{
				Type:   realtimeDomainTypeReceiptUpdated,
				ChatID: chatID,
				IDs:    []string{chatID},
			})
			chatTouched = true
		}

		if chatTouched {
			output = append(output, domainEvent{
				Type:   realtimeDomainTypeChatUpserted,
				ChatID: chatID,
				IDs:    []string{chatID},
			})
		}

		if len(messageUpsertIDs) > 0 {
			output = append(output, domainEvent{
				Type:   realtimeDomainTypeMessageUpserted,
				ChatID: chatID,
				IDs:    mapKeysSorted(messageUpsertIDs),
			})
		}
		if len(messageDeletedIDs) > 0 {
			output = append(output, domainEvent{
				Type:   realtimeDomainTypeMessageDeleted,
				ChatID: chatID,
				IDs:    mapKeysSorted(messageDeletedIDs),
			})
		}
	}

	return output
}

func mapKeysSorted(values map[string]struct{}) []string {
	output := make([]string, 0, len(values))
	for key := range values {
		if strings.TrimSpace(key) != "" {
			output = append(output, key)
		}
	}
	sort.Strings(output)
	return output
}
