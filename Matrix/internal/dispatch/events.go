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

	"go.mau.fi/gomuks/pkg/gomuks"
	"go.mau.fi/gomuks/pkg/hicli/database"
	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

const (
	wsDuplicateEventDebounce     = 250 * time.Millisecond
	wsFingerprintRetention       = 30 * time.Second
	wsFingerprintPruneInterval   = 5 * time.Second
	wsDefaultWriteTimeout        = 5 * time.Second
	wsKeepaliveInterval          = 30 * time.Second
	wsPingTimeout                = 5 * time.Second
	wsReadLimitBytes             = int64(64 * 1024)
	wsEventQueueSize             = 512
	wsSubscriptionsCommandType   = "subscriptions.set"
	wsSubscriptionsUpdatedType   = "subscriptions.updated"
	wsReadyType                  = "ready"
	wsDomainTypeChatUpserted     = "chat.upserted"
	wsDomainTypeChatDeleted      = "chat.deleted"
	wsDomainTypeMessageUpserted  = "message.upserted"
	wsDomainTypeMessageDeleted   = "message.deleted"
	wsDomainTypeReceiptUpdated   = "receipt.updated"
	wsErrorType                  = "error"
	wsErrorCodeInvalidCommand    = "INVALID_COMMAND"
	wsErrorCodeInvalidPayload    = "INVALID_PAYLOAD"
	wsErrorCodeNotSubscribed     = "NOT_SUBSCRIBED"
	wsErrorCodeInternal          = "INTERNAL_ERROR"
	wsWildcardSubscriptionChatID = "*"
	maxPushParticipants          = 8
)

type wsReadyMessage struct {
	Type    string   `json:"type"`
	Version int      `json:"version"`
	ChatIDs []string `json:"chatIDs"`
}

type wsSubscriptionsUpdatedMessage struct {
	Type      string   `json:"type"`
	RequestID string   `json:"requestID,omitempty"`
	ChatIDs   []string `json:"chatIDs"`
}

type wsErrorMessage struct {
	Type      string `json:"type"`
	RequestID string `json:"requestID,omitempty"`
	Code      string `json:"code"`
	Message   string `json:"message"`
}

type wsDomainEventMessage struct {
	Type    string         `json:"type"`
	Seq     int            `json:"seq"`
	TS      int64          `json:"ts"`
	ChatID  string         `json:"chatID"`
	IDs     []string       `json:"ids"`
	Entries []compatRecord `json:"entries,omitempty"`
}

type compatRecord map[string]any

type wsDomainEvent struct {
	Type   string
	ChatID string
	IDs    []string
}

type wsClientState struct {
	seq            int
	chatIDs        []string
	messageChatIDs []string
	writeMu        sync.Mutex
}

type realtimeSender func(any) error
type realtimePinger func(context.Context) error
type realtimeCloser func() error

type wsClient struct {
	id    uint64
	state *wsClientState
	send  realtimeSender
	ping  realtimePinger
	close realtimeCloser
}

type RealtimeConnection struct {
	hub    *wsHub
	id     uint64
	closed atomic.Bool
}

func (c *RealtimeConnection) Send(rawPayload []byte) error {
	if c == nil || c.closed.Load() {
		return errors.New("realtime connection is closed")
	}
	return c.hub.processRawPayload(c.id, rawPayload)
}

func (c *RealtimeConnection) Close() {
	if c == nil || c.closed.Swap(true) {
		return
	}
	c.hub.unregister(c.id, true)
}

type wsHub struct {
	server *Dispatcher

	mu           sync.RWMutex
	clients      map[uint64]*wsClient
	nextClientID uint64

	subscribeMu sync.Mutex
	unsubscribe func()

	eventQueue chan any
	overflowed atomic.Bool

	fingerprintMu        sync.Mutex
	recentFingerprints   map[string]time.Time
	lastFingerprintPrune time.Time
}

func newWSHub(server *Dispatcher) *wsHub {
	return &wsHub{
		server:             server,
		clients:            make(map[uint64]*wsClient),
		eventQueue:         make(chan any, wsEventQueueSize),
		recentFingerprints: make(map[string]time.Time),
	}
}

func (h *wsHub) ensureSubscription() error {
	h.subscribeMu.Lock()
	defer h.subscribeMu.Unlock()
	if h.unsubscribe != nil {
		return nil
	}

	buffer := h.server.rt.EventBuffer()
	if buffer == nil {
		return errors.New("gomuks runtime is not started")
	}
	listenerID, _ := buffer.Subscribe(0, nil, func(evt *gomuks.BufferedEvent) {
		if evt == nil {
			return
		}
		select {
		case h.eventQueue <- evt.Data:
		default:
			// Do not block sync; reconcile from SQLite after the burst instead.
			h.overflowed.Store(true)
		}
	})
	h.unsubscribe = func() {
		if currentBuffer := h.server.rt.EventBuffer(); currentBuffer != nil {
			currentBuffer.Unsubscribe(listenerID)
		}
	}
	go h.run()
	return nil
}

func (h *wsHub) run() {
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
			room, err := h.server.rt.Client().DB.Room.Get(context.Background(), complete.RoomID)
			if err == nil && room != nil {
				h.processSyncComplete(&jsoncmd.SyncComplete{Rooms: map[id.RoomID]*jsoncmd.SyncRoom{
					complete.RoomID: {Meta: room, Events: complete.Events},
				}})
			}
		}
		if h.overflowed.Swap(false) {
			h.mu.RLock()
			clients := make([]*wsClient, 0, len(h.clients))
			for _, client := range h.clients {
				clients = append(clients, client)
			}
			h.mu.RUnlock()
			for _, client := range clients {
				h.write(client, map[string]string{"type": "resync.required"})
			}
		}
	}
}

func (h *wsHub) register(send realtimeSender, ping realtimePinger, close realtimeCloser) uint64 {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.nextClientID++
	id := h.nextClientID
	h.clients[id] = &wsClient{
		id:    id,
		state: &wsClientState{chatIDs: []string{}},
		send:  send,
		ping:  ping,
		close: close,
	}
	return id
}

func (h *wsHub) open(send realtimeSender, ping realtimePinger, close realtimeCloser) (*RealtimeConnection, error) {
	if err := h.ensureSubscription(); err != nil {
		return nil, err
	}
	id := h.register(send, ping, close)
	client := h.client(id)
	if client == nil {
		return nil, errors.New("failed to register realtime client")
	}
	h.write(client, wsReadyMessage{
		Type:    wsReadyType,
		Version: 2,
		ChatIDs: []string{},
	})
	return &RealtimeConnection{hub: h, id: id}, nil
}

func (s *Dispatcher) OpenRealtime(send realtimeSender) (*RealtimeConnection, error) {
	return s.ws.open(send, nil, nil)
}

func (h *wsHub) client(id uint64) *wsClient {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return h.clients[id]
}

func (h *wsHub) unregister(id uint64, shouldClose bool) {
	h.mu.Lock()
	client := h.clients[id]
	delete(h.clients, id)
	h.mu.Unlock()
	if shouldClose && client != nil && client.close != nil {
		_ = client.close()
	}
}

func (h *wsHub) setSubscriptions(id uint64, chatIDs, messageChatIDs []string) {
	h.mu.Lock()
	if client, ok := h.clients[id]; ok && client.state != nil {
		client.state.chatIDs = chatIDs
		client.state.messageChatIDs = messageChatIDs
	}
	h.mu.Unlock()
}

func (h *wsHub) processSyncComplete(syncComplete *jsoncmd.SyncComplete) {
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
		detailed := domainEvent.Type == wsDomainTypeMessageUpserted || domainEvent.Type == wsDomainTypeMessageDeleted || domainEvent.Type == wsDomainTypeReceiptUpdated
		targets := h.subscribedTargets(domainEvent.ChatID, detailed)
		if len(targets) == 0 {
			continue
		}

		var entries []compatRecord
		if domainEvent.Type == wsDomainTypeMessageUpserted || domainEvent.Type == wsDomainTypeMessageDeleted {
			hydrated, err := h.server.hydrateMessagesForWSEvent(domainEvent.ChatID, domainEvent.IDs)
			if err != nil || (domainEvent.Type == wsDomainTypeMessageUpserted && len(hydrated) == 0) {
				continue
			}
			entries = hydrated
		}
		if domainEvent.Type == wsDomainTypeReceiptUpdated {
			hydrated, err := h.server.hydrateReceiptForWSEvent(domainEvent.ChatID)
			if err == nil && hydrated != nil {
				entries = []compatRecord{hydrated}
			}
		}
		if domainEvent.Type == wsDomainTypeChatUpserted {
			if summary := summaries[domainEvent.ChatID]; summary != nil {
				entries = []compatRecord{summary}
			}
		}

		for _, target := range targets {
			if target == nil || target.state == nil {
				continue
			}
			target.state.seq++
			payload := wsDomainEventMessage{
				Type:   domainEvent.Type,
				Seq:    target.state.seq,
				TS:     now.UnixMilli(),
				ChatID: domainEvent.ChatID,
				IDs:    domainEvent.IDs,
			}
			if len(entries) > 0 {
				payload.Entries = entries
			}
			h.write(target, payload)
		}
	}
}

func (h *wsHub) notifyNotificationPreferencesChanged() {
	h.mu.RLock()
	clients := make([]*wsClient, 0, len(h.clients))
	for _, client := range h.clients {
		clients = append(clients, client)
	}
	h.mu.RUnlock()
	for _, client := range clients {
		h.write(client, map[string]string{"type": "push.preferences.changed"})
	}
}

func (h *wsHub) subscribedTargets(chatID string, detailed bool) []*wsClient {
	h.mu.RLock()
	defer h.mu.RUnlock()

	output := make([]*wsClient, 0, len(h.clients))
	for _, client := range h.clients {
		if client == nil || client.state == nil {
			continue
		}
		ids := client.state.chatIDs
		if detailed {
			ids = client.state.messageChatIDs
		}
		if isWSSubscribed(ids, chatID) {
			output = append(output, client)
		}
	}
	return output
}

func (h *wsHub) dropDuplicate(fingerprint string, now time.Time) bool {
	h.fingerprintMu.Lock()
	defer h.fingerprintMu.Unlock()

	previousAt, hasPrevious := h.recentFingerprints[fingerprint]
	h.recentFingerprints[fingerprint] = now
	h.pruneFingerprintsLocked(now)

	return hasPrevious && now.Sub(previousAt) < wsDuplicateEventDebounce
}

func (h *wsHub) pruneFingerprintsLocked(now time.Time) {
	if now.Sub(h.lastFingerprintPrune) < wsFingerprintPruneInterval {
		return
	}
	h.lastFingerprintPrune = now
	for fingerprint, lastSeen := range h.recentFingerprints {
		if now.Sub(lastSeen) > wsFingerprintRetention {
			delete(h.recentFingerprints, fingerprint)
		}
	}
}

func (h *wsHub) write(client *wsClient, payload any) {
	if client == nil || client.state == nil || client.send == nil {
		return
	}

	client.state.writeMu.Lock()
	err := client.send(payload)
	client.state.writeMu.Unlock()
	if err != nil {
		h.unregister(client.id, true)
	}
}

func (s *Dispatcher) hydrateMessagesForWSEvent(chatID string, messageIDs []string) ([]compatRecord, error) {
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

	byID := make(map[string]compatRecord, len(events))
	for _, evt := range events {
		message, mapErr := s.mapEventToMessage(context.Background(), evt, room, lookup, reactionBundle{
			Names:     memberNames,
			Reactions: reactions,
		})
		if errors.Is(mapErr, errSkipEvent) || mapErr != nil {
			continue
		}
		serialized, marshalErr := toCompatRecord(message)
		if marshalErr != nil {
			continue
		}
		if transactionID := strings.TrimSpace(evt.TransactionID); transactionID != "" {
			serialized["transactionID"] = transactionID
		}
		byID[message.ID] = serialized
	}

	output := make([]compatRecord, 0, len(messageIDs))
	for _, messageID := range messageIDs {
		if entry, ok := byID[messageID]; ok {
			output = append(output, entry)
		}
	}
	return output, nil
}

func (s *Dispatcher) hydrateReceiptForWSEvent(chatID string) (compatRecord, error) {
	roomID := id.RoomID(chatID)
	otherReceipts, err := s.loadOtherReadReceipts(context.Background(), roomID)
	if err != nil {
		return nil, err
	}
	maxRead := computeMaxOtherRead(otherReceipts)
	if maxRead == 0 {
		return nil, nil
	}
	return compatRecord{
		"chatID":                 chatID,
		"lastReadByOtherSortKey": strconv.FormatInt(maxRead, 10),
	}, nil
}

func toCompatRecord(value any) (compatRecord, error) {
	raw, err := json.Marshal(value)
	if err != nil {
		return nil, err
	}
	var decoded compatRecord
	if err = json.Unmarshal(raw, &decoded); err != nil {
		return nil, err
	}
	return decoded, nil
}

func (h *wsHub) processRawPayload(clientID uint64, rawPayload []byte) error {
	client := h.client(clientID)
	if client == nil {
		return errors.New("realtime client not found")
	}

	var payload any
	if err := json.Unmarshal(rawPayload, &payload); err != nil {
		h.write(client, wsErrorMessage{
			Type:    wsErrorType,
			Code:    wsErrorCodeInvalidPayload,
			Message: "Invalid JSON payload",
		})
		return nil
	}
	payloadObject, ok := payload.(map[string]any)
	if !ok {
		h.write(client, wsErrorMessage{
			Type:    wsErrorType,
			Code:    wsErrorCodeInvalidPayload,
			Message: "Payload must be an object with a type field",
		})
		return nil
	}

	msgTypeRaw, hasType := payloadObject["type"]
	msgType, typeOK := msgTypeRaw.(string)
	requestID, _ := payloadObject["requestID"].(string)
	if !hasType || !typeOK {
		h.write(client, wsErrorMessage{
			Type:      wsErrorType,
			RequestID: requestID,
			Code:      wsErrorCodeInvalidPayload,
			Message:   "Payload must be an object with a type field",
		})
		return nil
	}
	if msgType != wsSubscriptionsCommandType {
		h.write(client, wsErrorMessage{
			Type:      wsErrorType,
			RequestID: requestID,
			Code:      wsErrorCodeInvalidCommand,
			Message:   "Unsupported command type: " + msgType,
		})
		return nil
	}

	for key := range payloadObject {
		if key != "type" && key != "requestID" && key != "chatIDs" && key != "messageChatIDs" {
			h.write(client, wsErrorMessage{
				Type:      wsErrorType,
				RequestID: requestID,
				Code:      wsErrorCodeInvalidPayload,
				Message:   "Invalid subscriptions payload",
			})
			return nil
		}
	}
	if rawRequestID, ok := payloadObject["requestID"]; ok {
		if _, castOK := rawRequestID.(string); !castOK {
			h.write(client, wsErrorMessage{
				Type:      wsErrorType,
				RequestID: requestID,
				Code:      wsErrorCodeInvalidPayload,
				Message:   "requestID must be a string",
			})
			return nil
		}
	}

	chatIDs, ok := decodeWSChatIDs(payloadObject["chatIDs"])
	if !ok {
		h.write(client, wsErrorMessage{
			Type:      wsErrorType,
			RequestID: requestID,
			Code:      wsErrorCodeInvalidPayload,
			Message:   "chatIDs must be an array of strings",
		})
		return nil
	}
	normalized, valid := normalizeWSChatIDs(chatIDs)
	if !valid {
		h.write(client, wsErrorMessage{
			Type:      wsErrorType,
			RequestID: requestID,
			Code:      wsErrorCodeInvalidPayload,
			Message:   "chatIDs cannot combine '*' with specific IDs",
		})
		return nil
	}

	messageIDs, ok := decodeWSChatIDs(payloadObject["messageChatIDs"])
	if !ok {
		return errors.New("messageChatIDs must be an array of strings")
	}
	messageIDs, valid = normalizeWSChatIDs(messageIDs)
	if !valid || (len(messageIDs) > 0 && messageIDs[0] == "*") {
		return errors.New("messageChatIDs must name explicit rooms")
	}
	h.setSubscriptions(clientID, normalized, messageIDs)
	h.write(client, wsSubscriptionsUpdatedMessage{
		Type:      wsSubscriptionsUpdatedType,
		RequestID: requestID,
		ChatIDs:   normalized,
	})
	return nil
}

func decodeWSChatIDs(raw any) ([]string, bool) {
	valueList, ok := raw.([]any)
	if !ok {
		return nil, false
	}
	output := make([]string, 0, len(valueList))
	for _, value := range valueList {
		asString, ok := value.(string)
		if !ok {
			return nil, false
		}
		asString = strings.TrimSpace(asString)
		if asString != "" {
			output = append(output, asString)
		}
	}
	return output, true
}

func normalizeWSChatIDs(chatIDs []string) ([]string, bool) {
	if len(chatIDs) == 0 {
		return []string{}, true
	}

	seen := make(map[string]struct{}, len(chatIDs))
	normalized := make([]string, 0, len(chatIDs))
	hasWildcard := false
	for _, chatID := range chatIDs {
		chatID = strings.TrimSpace(chatID)
		if chatID == "" {
			continue
		}
		if chatID == wsWildcardSubscriptionChatID {
			hasWildcard = true
		}
		if _, ok := seen[chatID]; ok {
			continue
		}
		seen[chatID] = struct{}{}
		normalized = append(normalized, chatID)
	}

	if hasWildcard {
		if len(normalized) != 1 || normalized[0] != wsWildcardSubscriptionChatID {
			return nil, false
		}
		return []string{wsWildcardSubscriptionChatID}, true
	}

	sort.Strings(normalized)
	return normalized, true
}

func isWSSubscribed(subscribedChatIDs []string, chatID string) bool {
	if len(subscribedChatIDs) == 0 {
		return false
	}
	for _, subscribed := range subscribedChatIDs {
		if subscribed == wsWildcardSubscriptionChatID || subscribed == chatID {
			return true
		}
	}
	return false
}

func mapSyncCompleteToDomainEvents(syncComplete *jsoncmd.SyncComplete) []wsDomainEvent {
	output := make([]wsDomainEvent, 0, len(syncComplete.Rooms)*2+len(syncComplete.LeftRooms))

	for _, leftRoom := range syncComplete.LeftRooms {
		chatID := strings.TrimSpace(leftRoom.String())
		if chatID == "" {
			continue
		}
		output = append(output, wsDomainEvent{
			Type:   wsDomainTypeChatDeleted,
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
			output = append(output, wsDomainEvent{
				Type:   wsDomainTypeReceiptUpdated,
				ChatID: chatID,
				IDs:    []string{chatID},
			})
			chatTouched = true
		}

		if chatTouched {
			output = append(output, wsDomainEvent{
				Type:   wsDomainTypeChatUpserted,
				ChatID: chatID,
				IDs:    []string{chatID},
			})
		}

		if len(messageUpsertIDs) > 0 {
			output = append(output, wsDomainEvent{
				Type:   wsDomainTypeMessageUpserted,
				ChatID: chatID,
				IDs:    mapKeysSorted(messageUpsertIDs),
			})
		}
		if len(messageDeletedIDs) > 0 {
			output = append(output, wsDomainEvent{
				Type:   wsDomainTypeMessageDeleted,
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
