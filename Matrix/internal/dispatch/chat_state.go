package dispatch

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"sort"
	"time"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

// The per-chat state the user sets: mute, archive (Beeper's inbox.done plus
// the Low Priority tag) and marked unread. Mute also honors room push rules.

var (
	accountDataInboxDone    = event.Type{Type: "com.beeper.inbox.done", Class: event.AccountDataEventType}
	accountDataMarkedUnread = event.Type{Type: "m.marked_unread", Class: event.AccountDataEventType}
)

type roomAccountDataState struct {
	IsMuted               bool
	MutedUntil            int64
	IsLowPriority         bool
	IsPinned              bool
	PinOrder              *float64
	IsMarkedUnread        bool
	MarkedUnreadUpdatedAt int64
	ArchivedUpdatedTS     *int64
	ArchivedAtOrder       *int64
}

type beeperInboxDoneContent struct {
	UpdatedTS *int64 `json:"updated_ts,omitempty"`
	AtOrder   *int64 `json:"at_order,omitempty"`
}

type markedUnreadContent struct {
	Unread bool  `json:"unread"`
	TS     int64 `json:"ts,omitempty"`
}

// EffectiveArchived reports Beeper's archive state. Marking a chat unread
// after archiving it moves it back to the inbox.
func (s roomAccountDataState) EffectiveArchived() bool {
	if s.MarkedUnreadUpdatedAt > 0 {
		if s.ArchivedUpdatedTS != nil && *s.ArchivedUpdatedTS < s.MarkedUnreadUpdatedAt {
			return false
		}
		if s.ArchivedUpdatedTS == nil && s.ArchivedAtOrder == nil {
			return false
		}
	}
	return s.ArchivedUpdatedTS != nil || s.ArchivedAtOrder != nil
}

// InArchive reports Relay's Archive category, which combines Beeper's Archive
// and Low Priority.
func (s roomAccountDataState) InArchive() bool {
	return s.EffectiveArchived() || s.IsLowPriority
}

// apply folds one account data event into the state. Unparseable content
// leaves the state unchanged.
func (s roomAccountDataState) apply(eventType string, content []byte) roomAccountDataState {
	switch eventType {
	case event.AccountDataRoomTags.Type:
		var tags event.TagEventContent
		if json.Unmarshal(content, &tags) == nil {
			_, s.IsLowPriority = tags.Tags[event.RoomTagLowPriority]
			favorite, pinned := tags.Tags[event.RoomTagFavourite]
			s.IsPinned = pinned
			s.PinOrder = nil
			if order, err := favorite.Order.Float64(); pinned && err == nil {
				s.PinOrder = &order
			}
		}
	case event.AccountDataBeeperMute.Type:
		var mute event.BeeperMuteEventContent
		if json.Unmarshal(content, &mute) == nil {
			s.IsMuted = mute.IsMuted()
			s.MutedUntil = mute.MutedUntil
		}
	case accountDataInboxDone.Type:
		var done beeperInboxDoneContent
		if json.Unmarshal(content, &done) == nil {
			s.ArchivedUpdatedTS = done.UpdatedTS
			s.ArchivedAtOrder = done.AtOrder
		}
	case accountDataMarkedUnread.Type:
		var unread markedUnreadContent
		if json.Unmarshal(content, &unread) == nil {
			s.IsMarkedUnread = unread.Unread
			s.MarkedUnreadUpdatedAt = unread.TS
		}
	}
	return s
}

// loadRoomAccountDataStates reads the given rooms' state, or every room's
// when none are given.
func (s *Dispatcher) loadRoomAccountDataStates(ctx context.Context, roomIDs ...id.RoomID) (map[id.RoomID]roomAccountDataState, error) {
	cli := s.rt.Client()
	if cli == nil || cli.Account == nil {
		return map[id.RoomID]roomAccountDataState{}, nil
	}
	query := `SELECT room_id, type, content FROM room_account_data WHERE user_id = $1`
	args := []any{cli.Account.UserID}
	if len(roomIDs) > 0 {
		query += " AND room_id IN (" + sqlSlots(len(roomIDs)) + ")"
		for _, roomID := range roomIDs {
			args = append(args, roomID)
		}
	}
	rows, err := cli.DB.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to query room account data: %w", err)
	}
	defer rows.Close()

	states := make(map[id.RoomID]roomAccountDataState)
	for rows.Next() {
		var (
			roomIDRaw string
			eventType string
			content   []byte
		)
		if err = rows.Scan(&roomIDRaw, &eventType, &content); err != nil {
			return nil, fmt.Errorf("failed to scan room account data: %w", err)
		}
		if roomIDRaw == "" {
			continue
		}
		roomID := id.RoomID(roomIDRaw)
		states[roomID] = states[roomID].apply(eventType, content)
	}
	if err = rows.Err(); err != nil {
		return nil, fmt.Errorf("room account data query failed: %w", err)
	}
	if err = s.applyRoomMuteRules(ctx, states, roomIDs); err != nil {
		return nil, err
	}
	return states, nil
}

// muteChat updates both Beeper's mute state and the homeserver's room rule.
func (s *Dispatcher) muteChat(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID string `json:"chatID,omitempty"`
		Muted  *bool  `json:"muted,omitempty"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID, err := required(req.ChatID, "chatID")
	if err != nil {
		return nil, err
	}
	roomID := id.RoomID(chatID)
	var content event.BeeperMuteEventContent
	if req.Muted == nil || *req.Muted {
		content.MutedUntil = -1 // Muted forever; zero means not muted.
	}
	if err = s.rt.Client().Client.SetRoomAccountData(ctx, roomID, event.AccountDataBeeperMute.Type, content); err != nil {
		return nil, fmt.Errorf("failed to set mute state: %w", err)
	}
	// The homeserver echoes room account data through sync, but a message can
	// arrive before that echo. Update the local view before Swift exports the
	// new mute preferences to the notification gateway.
	s.cacheRoomAccountData(ctx, roomID, event.AccountDataBeeperMute, content)
	ruleErr := s.setRoomMuteRule(ctx, roomID, content.IsMuted())
	refreshErr := s.refreshRoomMuteRules(ctx)
	if ruleErr != nil {
		return nil, fmt.Errorf("failed to update chat notification rule: %w", ruleErr)
	}
	if refreshErr != nil {
		return nil, fmt.Errorf("chat setting saved, but notification state could not be refreshed: %w", refreshErr)
	}
	return s.getChat(ctx, input)
}

func (s *Dispatcher) archiveChat(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		Archived *bool  `json:"archived,omitempty"`
		ChatID   string `json:"chatID,omitempty"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID, err := required(req.ChatID, "chatID")
	if err != nil {
		return nil, err
	}
	roomID := id.RoomID(chatID)
	content := map[string]any{}
	if req.Archived == nil || *req.Archived {
		content["updated_ts"] = time.Now().UnixMilli()
	}
	if err = s.rt.Client().Client.SetRoomAccountData(ctx, roomID, accountDataInboxDone.Type, content); err != nil {
		return nil, fmt.Errorf("failed to set archive state: %w", err)
	}
	// Relay's Archive is Beeper's Archive. Both archiving and unarchiving drop
	// an existing Low Priority tag, preserving favorites and every other tag.
	if err = s.clearLowPriority(ctx, roomID); err != nil {
		return nil, fmt.Errorf("failed to remove low priority state: %w", err)
	}
	// Cache the new archive state before a concurrent message checks eligibility.
	s.cacheRoomAccountData(ctx, roomID, accountDataInboxDone, content)
	return wire.Success, nil
}

// Marked unread is synced account data, independent of message counts and
// read receipts. Beeper's timestamp also moves archived chats into the inbox.
func (s *Dispatcher) setChatMarkedUnread(ctx context.Context, roomID id.RoomID, unread bool) error {
	states, err := s.loadRoomAccountDataStates(ctx, roomID)
	if err != nil {
		return err
	}
	content := markedUnreadContent{Unread: unread, TS: states[roomID].MarkedUnreadUpdatedAt}
	if unread {
		content.TS = time.Now().UnixMilli()
	}
	// Keep the timestamp when clearing the flag so reading a chat does not
	// restore an archive state that marking it unread already superseded.
	if err = s.rt.Client().Client.SetRoomAccountData(ctx, roomID, accountDataMarkedUnread.Type, content); err != nil {
		return fmt.Errorf("failed to set unread state: %w", err)
	}
	s.cacheRoomAccountData(ctx, roomID, accountDataMarkedUnread, content)
	return nil
}

// cacheRoomAccountData stores account data the homeserver accepted ahead of
// its sync echo. Failure only delays the local view until that echo.
func (s *Dispatcher) cacheRoomAccountData(ctx context.Context, roomID id.RoomID, eventType event.Type, content any) {
	cli := s.rt.Client()
	if cli == nil || cli.Account == nil {
		return
	}
	raw, err := json.Marshal(content)
	if err == nil {
		_, err = cli.DB.AccountData.PutRoom(ctx, cli.Account.UserID, roomID, eventType, raw)
	}
	if err != nil {
		log.Printf("failed to cache local %s for %s: %v", eventType.Type, roomID, err)
	}
}

func (s *Dispatcher) clearLowPriority(ctx context.Context, roomID id.RoomID) error {
	cli := s.rt.Client()
	var raw []byte
	err := cli.DB.QueryRow(ctx, `SELECT content FROM room_account_data WHERE user_id=? AND room_id=? AND type='m.tag'`, cli.Account.UserID, roomID).Scan(&raw)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	} else if err != nil {
		return err
	}
	var tags event.TagEventContent
	if err = json.Unmarshal(raw, &tags); err != nil {
		return err
	}
	if _, exists := tags.Tags[event.RoomTagLowPriority]; !exists {
		return nil
	}
	if err = cli.Client.RemoveTag(ctx, roomID, event.RoomTagLowPriority); err != nil && !errors.Is(err, mautrix.MNotFound) {
		return err
	}
	delete(tags.Tags, event.RoomTagLowPriority)
	raw, err = json.Marshal(tags)
	if err != nil {
		return err
	}
	_, err = cli.DB.AccountData.PutRoom(ctx, cli.Account.UserID, roomID, event.AccountDataRoomTags, raw)
	return err
}

type blockedRoom struct {
	// Field order matches the keys' sorted order in earlier releases.
	BlockedUntil int64  `json:"blockedUntil"`
	RoomID       string `json:"roomID"`
}

// PushPreferences exports the rooms whose notifications the push gateway
// suppresses for ordinary messages: muted rooms until their expiry, archived
// ones forever (-1). The gateway lets personal mentions bypass these blocks.
// This preference export contains no Matrix credentials, message content, or keys.
func (s *Dispatcher) PushPreferences(ctx context.Context) (any, error) {
	states, err := s.loadRoomAccountDataStates(ctx)
	if err != nil {
		return nil, err
	}
	rooms := make([]blockedRoom, 0)
	for roomID, state := range states {
		until := state.MutedUntil
		if state.InArchive() {
			until = -1
		}
		if until != 0 {
			rooms = append(rooms, blockedRoom{BlockedUntil: until, RoomID: string(roomID)})
		}
	}
	sort.Slice(rooms, func(i, j int) bool { return rooms[i].RoomID < rooms[j].RoomID })
	return map[string]any{"rooms": rooms}, nil
}
