package dispatch

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"

	"strconv"
	"strings"
	"time"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/compat"
	"relay/core/internal/cursor"
	errs "relay/core/internal/errors"
)

const (
	searchChatsDefaultLimit    = 50
	searchChatsMaxLimit        = 200
	searchMessagesDefaultLimit = 20
	searchMessagesMaxLimit     = 20
	searchContactsDefaultLimit = 50
	searchContactsMaxLimit     = 200
	unifiedChatSectionLimit    = 30
	unifiedMessageSectionLimit = 20

	searchMessagesScanBatchSize  = 500
	searchMessagesScanMaxEvents  = 5000
	searchMessagesScanMaxBatches = 20

	contactSourceScoreCloudList    = 100
	contactSourceScoreParticipants = 120
	contactSourceScoreDirectory    = 200
	contactSourceScoreLookup       = 300
	contactLookupMaxCandidates     = 4
)

type searchChatsParams struct {
	Query              string
	Scope              string
	Inbox              string
	Type               string
	Direction          string
	Cursor             *cursor.ChatCursor
	Limit              int
	UnreadOnly         bool
	IncludeMuted       bool
	LastActivityBefore *time.Time
	LastActivityAfter  *time.Time
	AccountIDs         []string
}

func (s *Dispatcher) searchChats(w http.ResponseWriter, r *http.Request) error {
	params, err := parseSearchChatsParams(r)
	if err != nil {
		return err
	}
	out, err := s.searchChatsCore(r.Context(), params)
	if err != nil {
		return err
	}
	return writeJSON(w, out)
}

func (s *Dispatcher) archiveChat(w http.ResponseWriter, r *http.Request) error {
	var req struct {
		Archived *bool  `json:"archived,omitempty"`
		ChatID   string `json:"chatID,omitempty"`
	}
	if err := decodeOptionalJSON(r, &req); err != nil {
		return err
	}
	chatID := readChatID(r, req.ChatID)
	if chatID == "" {
		return errs.Validation(map[string]any{"chatID": "chatID is required"})
	}
	archived := true
	if req.Archived != nil {
		archived = *req.Archived
	}

	var content any = map[string]any{}
	if archived {
		content = map[string]any{"updated_ts": time.Now().UnixMilli()}
	}
	if err := s.rt.Client().Client.SetRoomAccountData(r.Context(), id.RoomID(chatID), "com.beeper.inbox.done", content); err != nil {
		return errs.Internal(fmt.Errorf("failed to set archive state: %w", err))
	}
	// Archive actions always use Beeper Archive. Unarchive also removes an
	// existing Low Priority tag, while preserving favorites and every other tag.
	if err := s.clearLowPriority(r.Context(), id.RoomID(chatID)); err != nil {
		return errs.Internal(fmt.Errorf("failed to remove low priority state: %w", err))
	}
	// Cache the new archive state before a concurrent message checks eligibility.
	if cli := s.rt.Client(); cli != nil && cli.Account != nil {
		raw, marshalErr := json.Marshal(content)
		if marshalErr == nil {
			_, cacheErr := cli.DB.AccountData.PutRoom(r.Context(), cli.Account.UserID, id.RoomID(chatID),
				event.Type{Type: "com.beeper.inbox.done", Class: event.AccountDataEventType}, raw)
			if cacheErr != nil {
				log.Printf("cache archive state: %v", cacheErr)
			}
		}
	}
	return writeJSON(w, compat.ActionSuccessOutput{Success: true})
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

	items := make([]compat.Chat, 0, params.Limit+1)
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
		if !params.IncludeMuted && state.IsMuted {
			continue
		}
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
		if params.Type != "any" && params.Type != "" && string(chat.Type) != params.Type {
			continue
		}
		if params.UnreadOnly && chat.UnreadCount <= 0 && !chat.IsMarkedUnread {
			continue
		}
		if params.LastActivityBefore != nil && mustParseRFC3339(chat.LastActivity) >= params.LastActivityBefore.UnixMilli() {
			continue
		}
		if params.LastActivityAfter != nil && mustParseRFC3339(chat.LastActivity) <= params.LastActivityAfter.UnixMilli() {
			continue
		}
		if !matchesChatQuery(chat, params.Query, params.Scope) {
			continue
		}

		items = append(items, chat)
		if len(items) > params.Limit {
			break
		}
	}

	hasMore := len(items) > params.Limit
	if hasMore {
		items = items[:params.Limit]
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

func parseSearchChatsParams(r *http.Request) (searchChatsParams, error) {
	direction, err := parseDirection(r.URL.Query().Get("direction"))
	if err != nil {
		return searchChatsParams{}, err
	}
	cursorValue, err := parseChatCursor(r.URL.Query().Get("cursor"))
	if err != nil {
		return searchChatsParams{}, err
	}
	limit, err := parseOptionalLimit(r.URL.Query().Get("limit"), searchChatsDefaultLimit, 1, searchChatsMaxLimit, "limit")
	if err != nil {
		return searchChatsParams{}, err
	}
	unreadOnly, err := parseOptionalBool(r.URL.Query().Get("unreadOnly"), false, "unreadOnly")
	if err != nil {
		return searchChatsParams{}, err
	}
	includeMuted, err := parseOptionalBool(r.URL.Query().Get("includeMuted"), true, "includeMuted")
	if err != nil {
		return searchChatsParams{}, err
	}
	scope := strings.TrimSpace(r.URL.Query().Get("scope"))
	if scope == "" {
		scope = "titles"
	}
	if scope != "titles" && scope != "participants" {
		return searchChatsParams{}, errs.Validation(map[string]any{"scope": "must be one of: titles, participants"})
	}
	inbox := strings.TrimSpace(r.URL.Query().Get("inbox"))
	if inbox != "" && inbox != "primary" && inbox != "archive" && inbox != "unread" {
		return searchChatsParams{}, errs.Validation(map[string]any{"inbox": "must be one of: primary, archive, unread"})
	}
	chatType := strings.TrimSpace(r.URL.Query().Get("type"))
	if chatType == "" {
		chatType = "any"
	}
	if chatType != "any" && chatType != "single" && chatType != "group" {
		return searchChatsParams{}, errs.Validation(map[string]any{"type": "must be one of: any, single, group"})
	}
	lastActivityBefore, err := parseOptionalRFC3339(r.URL.Query().Get("lastActivityBefore"), "lastActivityBefore")
	if err != nil {
		return searchChatsParams{}, err
	}
	lastActivityAfter, err := parseOptionalRFC3339(r.URL.Query().Get("lastActivityAfter"), "lastActivityAfter")
	if err != nil {
		return searchChatsParams{}, err
	}
	return searchChatsParams{
		Query:              strings.TrimSpace(r.URL.Query().Get("query")),
		Scope:              scope,
		Inbox:              inbox,
		Type:               chatType,
		Direction:          direction,
		Cursor:             cursorValue,
		Limit:              limit,
		UnreadOnly:         unreadOnly,
		IncludeMuted:       includeMuted,
		LastActivityBefore: lastActivityBefore,
		LastActivityAfter:  lastActivityAfter,
		AccountIDs:         parseAccountIDs(r),
	}, nil
}

func parseOptionalLimit(raw string, defaultValue, minValue, maxValue int, field string) (int, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return defaultValue, nil
	}
	parsed, err := strconv.Atoi(raw)
	if err != nil {
		return 0, errs.Validation(map[string]any{field: "must be an integer"})
	}
	if parsed < minValue || parsed > maxValue {
		return 0, errs.Validation(map[string]any{field: fmt.Sprintf("must be between %d and %d", minValue, maxValue)})
	}
	return parsed, nil
}

func parseOptionalBool(raw string, defaultValue bool, field string) (bool, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return defaultValue, nil
	}
	value, err := strconv.ParseBool(raw)
	if err != nil {
		return false, errs.Validation(map[string]any{field: "must be true or false"})
	}
	return value, nil
}

func parseOptionalRFC3339(raw, field string) (*time.Time, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil, nil
	}
	parsed, err := time.Parse(time.RFC3339, raw)
	if err != nil {
		return nil, errs.Validation(map[string]any{field: "must be an RFC3339 datetime"})
	}
	return &parsed, nil
}

func matchesChatQuery(chat compat.Chat, query, scope string) bool {
	query = strings.TrimSpace(query)
	if query == "" {
		return true
	}
	tokens := strings.Fields(strings.ToLower(query))
	if len(tokens) == 0 {
		return true
	}
	var haystack string
	if scope == "participants" {
		var parts []string
		for _, participant := range chat.Participants.Items {
			parts = append(parts, participant.FullName, participant.Username, participant.ID)
		}
		haystack = strings.ToLower(strings.Join(parts, " "))
	} else {
		haystack = strings.ToLower(chat.Title + " " + chat.Network)
	}
	for _, token := range tokens {
		if !strings.Contains(haystack, token) {
			return false
		}
	}
	return true
}
