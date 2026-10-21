package dispatch

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"

	"strings"
	"time"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/compat"
	"relay/core/internal/cursor"
)

const searchChatsLimit = 50

type chatListInput struct {
	Query      string   `json:"query"`
	Inbox      string   `json:"inbox"`
	AccountIDs []string `json:"accountIDs"`
	Cursor     string   `json:"cursor"`
	Direction  string   `json:"direction"`
}

type searchChatsParams struct {
	Query      string
	Inbox      string
	AccountIDs []string
	Cursor     *cursor.ChatCursor
	Direction  string
}

func (s *Dispatcher) searchChats(ctx context.Context, input json.RawMessage) (any, error) {
	var req chatListInput
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	direction, err := parseDirection(req.Direction)
	if err != nil {
		return nil, err
	}
	position, err := parseChatCursor(req.Cursor)
	if err != nil {
		return nil, err
	}
	return s.searchChatsCore(ctx, searchChatsParams{
		Query: strings.TrimSpace(req.Query), Inbox: strings.TrimSpace(req.Inbox),
		AccountIDs: req.AccountIDs, Cursor: position, Direction: direction,
	})
}

func (s *Dispatcher) archiveChat(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		Archived *bool  `json:"archived,omitempty"`
		ChatID   string `json:"chatID,omitempty"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID := strings.TrimSpace(req.ChatID)
	if chatID == "" {
		return nil, errors.New("chatID is required")
	}
	archived := true
	if req.Archived != nil {
		archived = *req.Archived
	}

	var content any = map[string]any{}
	if archived {
		content = map[string]any{"updated_ts": time.Now().UnixMilli()}
	}
	if err := s.rt.Client().Client.SetRoomAccountData(ctx, id.RoomID(chatID), "com.beeper.inbox.done", content); err != nil {
		return nil, fmt.Errorf("failed to set archive state: %w", err)
	}
	// Archive actions always use Beeper Archive. Unarchive also removes an
	// existing Low Priority tag, while preserving favorites and every other tag.
	if err := s.clearLowPriority(ctx, id.RoomID(chatID)); err != nil {
		return nil, fmt.Errorf("failed to remove low priority state: %w", err)
	}
	// Cache the new archive state before a concurrent message checks eligibility.
	if cli := s.rt.Client(); cli != nil && cli.Account != nil {
		raw, marshalErr := json.Marshal(content)
		if marshalErr == nil {
			_, cacheErr := cli.DB.AccountData.PutRoom(ctx, cli.Account.UserID, id.RoomID(chatID),
				event.Type{Type: "com.beeper.inbox.done", Class: event.AccountDataEventType}, raw)
			if cacheErr != nil {
				log.Printf("cache archive state: %v", cacheErr)
			}
		}
	}
	return compat.ActionSuccessOutput{Success: true}, nil
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
	if err := json.Unmarshal(raw, &tags); err != nil {
		return err
	}
	if _, exists := tags.Tags[event.RoomTagLowPriority]; !exists {
		return nil
	}
	if err := cli.Client.RemoveTag(ctx, roomID, event.RoomTagLowPriority); err != nil && !errors.Is(err, mautrix.MNotFound) {
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

func (s *Dispatcher) searchChatsCore(ctx context.Context, params searchChatsParams) (compat.SearchChatsOutput, error) {
	lookup, err := s.buildAccountLookup(ctx)
	if err != nil {
		return compat.SearchChatsOutput{}, err
	}
	rooms, err := s.loadRoomsSorted(ctx)
	if err != nil {
		return compat.SearchChatsOutput{}, err
	}
	roomStates, err := s.loadRoomAccountDataStates(ctx)
	if err != nil {
		return compat.SearchChatsOutput{}, err
	}
	readKeys, _ := s.loadLastReadSortKeys(ctx)

	items := make([]compat.Chat, 0, searchChatsLimit+1)
	for _, room := range rooms {
		if params.Cursor != nil {
			if params.Direction == "before" && !roomIsOlderThanCursor(room, params.Cursor) {
				continue
			}
			if params.Direction == "after" && !roomIsNewerThanCursor(room, params.Cursor) {
				continue
			}
		}
		state := roomStates[room.ID]
		if !roomMatchesInbox(room, state, params.Inbox) {
			continue
		}
		chat, mapErr := s.mapRoomToChat(ctx, room, lookup, chatPreviewParticipants, true, state, readKeys[room.ID])
		if mapErr != nil {
			continue
		}
		if len(params.AccountIDs) > 0 && !equalsAny(chat.AccountID, params.AccountIDs) {
			continue
		}
		if !matchesChatQuery(chat, params.Query) {
			continue
		}

		items = append(items, chat)
		if len(items) > searchChatsLimit {
			break
		}
	}

	hasMore := len(items) > searchChatsLimit
	if hasMore {
		items = items[:searchChatsLimit]
	}
	var oldestCursor *string
	var newestCursor *string
	if len(items) > 0 {
		firstTS := mustParseRFC3339(items[0].LastActivity)
		lastTS := mustParseRFC3339(items[len(items)-1].LastActivity)
		newestEncoded, newErr := cursor.Encode(cursor.ChatCursor{TS: firstTS, RoomID: items[0].ID})
		oldestEncoded, oldErr := cursor.Encode(cursor.ChatCursor{TS: lastTS, RoomID: items[len(items)-1].ID})
		if firstErr(newErr, oldErr) == nil {
			newestCursor = &newestEncoded
			oldestCursor = &oldestEncoded
		}
	}
	return compat.SearchChatsOutput{
		Items:        items,
		HasMore:      hasMore,
		OldestCursor: oldestCursor,
		NewestCursor: newestCursor,
	}, nil
}

func matchesChatQuery(chat compat.Chat, query string) bool {
	query = strings.TrimSpace(query)
	if query == "" {
		return true
	}
	tokens := strings.Fields(strings.ToLower(query))
	if len(tokens) == 0 {
		return true
	}
	haystack := strings.ToLower(chat.Title + " " + chat.Network)
	for _, token := range tokens {
		if !strings.Contains(haystack, token) {
			return false
		}
	}
	return true
}
