package dispatch

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

const (
	chatPageSize            = 25
	searchChatsLimit        = 50
	chatPreviewParticipants = 5
)

type chatListInput struct {
	Query      string   `json:"query"`
	Inbox      string   `json:"inbox"`
	AccountIDs []string `json:"accountIDs"`
	// The last chat already shown; the page starts after it.
	BeforeTS     int64  `json:"beforeTS"`
	BeforeRoomID string `json:"beforeRoomID"`
}

// listChats returns up to limit chats in sidebar order. It serves both the
// sidebar pages and search, which differ only in their limit.
func (s *Dispatcher) listChats(ctx context.Context, input json.RawMessage, limit int) (any, error) {
	var req chatListInput
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	return s.loadChatList(ctx, req, limit)
}

// loadChatList walks rooms newest first until it has a page of matches. Inbox
// and title filters run before the member and preview queries, so a search or
// an archive view doesn't summarize rooms it then discards.
func (s *Dispatcher) loadChatList(ctx context.Context, req chatListInput, limit int) (wire.ListChatsOutput, error) {
	lookup, err := s.buildAccountLookup(ctx)
	if err != nil {
		return wire.ListChatsOutput{}, err
	}
	inbox := strings.TrimSpace(req.Inbox)
	queryTokens := strings.Fields(strings.ToLower(req.Query))
	var position *roomPosition
	if req.BeforeTS > 0 {
		position = &roomPosition{ts: req.BeforeTS, roomID: req.BeforeRoomID}
	}

	items := make([]wire.Chat, 0, limit+1)
	for len(items) <= limit {
		rooms, err := s.loadRoomPage(ctx, position)
		if err != nil {
			return wire.ListChatsOutput{}, err
		}
		if len(rooms) == 0 {
			break
		}
		last := rooms[len(rooms)-1]
		position = &roomPosition{ts: last.SortingTimestamp.UnixMilli(), roomID: string(last.ID)}

		states, err := s.loadRoomAccountDataStates(ctx, roomIDs(rooms)...)
		if err != nil {
			return wire.ListChatsOutput{}, err
		}
		var candidates []*database.Room
		for _, room := range rooms {
			if roomMatchesInbox(room, states[room.ID], inbox) && titleMatches(roomTitle(room), queryTokens) {
				candidates = append(candidates, room)
			}
		}
		if len(candidates) > 0 {
			reads, _ := s.loadLastReadSortKeys(ctx, roomIDs(candidates)...)
			summaries, err := s.loadChatSummaries(ctx, candidates, chatPreviewParticipants, lookup)
			if err != nil {
				return wire.ListChatsOutput{}, err
			}
			for _, room := range candidates {
				if len(req.AccountIDs) > 0 && !slices.Contains(req.AccountIDs, lookup.roomAccounts[room.ID]) {
					continue
				}
				items = append(items, s.mapRoomToChat(room, summaries[room.ID], lookup, states[room.ID], reads[room.ID]))
				if len(items) > limit {
					break
				}
			}
		}
		if len(rooms) < roomPageSize {
			break
		}
	}

	hasMore := len(items) > limit
	if hasMore {
		items = items[:limit]
	}
	output := wire.ListChatsOutput{Items: items, HasMore: hasMore}
	// Pins are independent of the activity cursor, including quiet chats far
	// beyond the first page. Search continues to return ordinary matching rows.
	if req.BeforeRoomID == "" && strings.TrimSpace(req.Query) == "" {
		output.Pinned, err = s.loadPinnedChats(ctx, req, lookup)
		if err != nil {
			return wire.ListChatsOutput{}, err
		}
	}
	return output, nil
}

func roomMatchesInbox(room *database.Room, state roomAccountDataState, inbox string) bool {
	switch inbox {
	case "primary":
		return !state.InArchive()
	case "archive":
		return state.InArchive()
	case "unread":
		return room.UnreadMessages > 0 || state.IsMarkedUnread
	default:
		return true
	}
}

func titleMatches(title string, tokens []string) bool {
	title = strings.ToLower(title)
	for _, token := range tokens {
		if !strings.Contains(title, token) {
			return false
		}
	}
	return true
}

func (s *Dispatcher) getChat(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID              string `json:"chatID"`
		MaxParticipantCount int    `json:"maxParticipantCount"`
	}
	req.MaxParticipantCount = chatPreviewParticipants
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID, err := required(req.ChatID, "chatID")
	if err != nil {
		return nil, err
	}
	if req.MaxParticipantCount < 1 || req.MaxParticipantCount > 500 {
		return nil, errors.New("maxParticipantCount: must be between 1 and 500")
	}
	lookup, err := s.buildAccountLookup(ctx)
	if err != nil {
		return nil, err
	}
	room, err := s.rt.Client().DB.Room.Get(ctx, id.RoomID(chatID))
	if err != nil {
		return nil, fmt.Errorf("failed to read room metadata: %w", err)
	}
	if room == nil {
		return nil, errors.New("Chat not found")
	}
	states, err := s.loadRoomAccountDataStates(ctx, room.ID)
	if err != nil {
		return nil, err
	}
	reads, _ := s.loadLastReadSortKeys(ctx, room.ID)
	summaries, err := s.loadChatSummaries(ctx, []*database.Room{room}, req.MaxParticipantCount, lookup)
	if err != nil {
		return nil, err
	}
	return s.mapRoomToChat(room, summaries[room.ID], lookup, states[room.ID], reads[room.ID]), nil
}

func roomTitle(room *database.Room) string {
	if room.Name != nil {
		if title := strings.TrimSpace(*room.Name); title != "" {
			return title
		}
	}
	return string(room.ID)
}

func roomIDs(rooms []*database.Room) []id.RoomID {
	ids := make([]id.RoomID, len(rooms))
	for i, room := range rooms {
		ids[i] = room.ID
	}
	return ids
}

func (s *Dispatcher) mapRoomToChat(room *database.Room, summary *chatSummary, lookup *accountLookup, state roomAccountDataState, lastReadSortKey string) wire.Chat {
	chatType := wire.ChatTypeGroup
	if room.DMUserID != nil && *room.DMUserID != "" {
		chatType = wire.ChatTypeSingle
	}
	chat := wire.Chat{
		ID:        string(room.ID),
		AccountID: lookup.roomAccounts[room.ID],
		Title:     roomTitle(room),
		Type:      chatType,
		Participants: wire.Participants{
			Items:   summary.members,
			HasMore: summary.total > len(summary.members),
			Total:   int64(summary.total),
		},
		UnreadCount:            int64(room.UnreadMessages),
		IsArchived:             state.InArchive(),
		IsMuted:                state.IsMuted,
		IsPinned:               state.IsPinned,
		PinOrder:               state.PinOrder,
		IsMarkedUnread:         state.IsMarkedUnread,
		LastReadMessageSortKey: lastReadSortKey,
	}
	if room.Avatar != nil {
		if avatarURL := room.Avatar.String(); avatarURL != "" && avatarURL != "mxc://" {
			chat.ImgURL = avatarURL
		}
	}
	if ts := room.SortingTimestamp.UnixMilli(); ts > 0 {
		chat.LastActivity = time.UnixMilli(ts).UTC()
	}
	if summary.preview != nil {
		if preview, err := s.mapEventToMessage(summary.preview, summary.names, nil); err == nil {
			if !preview.IsSender {
				if lastReadSortKey != "" {
					lastRead, _ := strconv.ParseInt(lastReadSortKey, 10, 64)
					preview.IsUnread = isUnreadAfter(preview.SortKey, lastRead)
				} else {
					preview.IsUnread = chat.UnreadCount > 0
				}
			}
			chat.Preview = &preview
		}
	}
	return chat
}
