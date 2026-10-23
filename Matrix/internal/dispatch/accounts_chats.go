package dispatch

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/compat"
)

const (
	bridgeStateEventType    = "com.beeper.bridge_state"
	chatPageSize            = 25
	searchChatsLimit        = 50
	chatPreviewParticipants = 5
)

const roomSelectBaseQuery = `
	SELECT room_id, creation_content, tombstone_content, name, name_quality,
	       avatar, explicit_avatar, dm_user_id, topic, canonical_alias,
	       lazy_load_summary, encryption_event, has_member_list, preview_event_rowid, sorting_timestamp,
	       unread_highlights, unread_notifications, unread_messages, marked_unread, prev_batch
	FROM room
`

const roomAccountDataSelectQuery = `SELECT room_id, type, content FROM room_account_data WHERE user_id = $1`

// bridgeStateContent matches the com.beeper.bridge_state account data event.
type bridgeStateContent struct {
	Bridges map[string]bridgeEntry `json:"bridges"`
}

type bridgeEntry struct {
	BridgeState bridgeRunState               `json:"bridgeState"`
	RemoteState map[string]bridgeRemoteState `json:"remoteState"`
}

type bridgeRunState struct {
	StateEvent string `json:"stateEvent"`
}

type bridgeRemoteState struct {
	RemoteProfile map[string]any `json:"remote_profile"`
	StateEvent    string         `json:"state_event"`
}

type roomAccount struct{ accountID, network string }

type accountLookup struct {
	roomAccounts map[id.RoomID]roomAccount
	Accounts     []compat.Account
	ByBridge     map[string][]compat.Account
	// Bridge IDs longest first, so the most specific prefix matches.
	bridgeIDs []string
}

type roomAccountDataState struct {
	IsMuted               bool
	MutedUntil            int64
	IsLowPriority         bool
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

// Relay presents Beeper's Archive and Low Priority as one Archive category.
func (s roomAccountDataState) InArchive() bool {
	return s.EffectiveArchived() || s.IsLowPriority
}

func applyRoomAccountDataContent(state roomAccountDataState, eventType string, content []byte) roomAccountDataState {
	switch eventType {
	case event.AccountDataRoomTags.Type:
		var tags event.TagEventContent
		if unmarshalErr := json.Unmarshal(content, &tags); unmarshalErr != nil {
			return state
		}
		_, state.IsLowPriority = tags.Tags[event.RoomTagLowPriority]
	case event.AccountDataBeeperMute.Type:
		var mute event.BeeperMuteEventContent
		if unmarshalErr := json.Unmarshal(content, &mute); unmarshalErr != nil {
			return state
		}
		state.IsMuted = mute.IsMuted()
		state.MutedUntil = mute.MutedUntil
	case "com.beeper.inbox.done":
		var done beeperInboxDoneContent
		if unmarshalErr := json.Unmarshal(content, &done); unmarshalErr != nil {
			return state
		}
		state.ArchivedUpdatedTS = done.UpdatedTS
		state.ArchivedAtOrder = done.AtOrder
	case "m.marked_unread":
		var unread markedUnreadContent
		if unmarshalErr := json.Unmarshal(content, &unread); unmarshalErr != nil {
			return state
		}
		state.IsMarkedUnread = unread.Unread
		state.MarkedUnreadUpdatedAt = unread.TS
	}
	return state
}

func (s *Dispatcher) getSession(ctx context.Context, input json.RawMessage) (any, error) {
	accounts, err := s.loadAccounts(ctx)
	if err != nil {
		return nil, err
	}

	cli := s.rt.Client()
	user := newUser(string(cli.Account.UserID), "", "", "", true)
	for _, account := range accounts {
		if account.User.IsSelf && account.User.FullName != "" && account.User.FullName != account.User.ID {
			user = account.User
			break
		}
	}
	if profile, profileErr := cli.Client.GetProfile(ctx, cli.Account.UserID); profileErr == nil && profile != nil &&
		(strings.TrimSpace(profile.DisplayName) != "" || !profile.AvatarURL.IsEmpty()) {
		user = newUser(string(cli.Account.UserID), profile.DisplayName, profile.AvatarURL.String(), "", true)
	}

	return compat.SessionOutput{User: user, Accounts: accounts}, nil
}

func (s *Dispatcher) buildAccountLookup(ctx context.Context) (*accountLookup, error) {
	accounts, err := s.loadAccounts(ctx)
	if err != nil {
		return nil, err
	}
	lookup := &accountLookup{
		Accounts:     accounts,
		ByBridge:     make(map[string][]compat.Account),
		roomAccounts: make(map[id.RoomID]roomAccount),
	}
	for _, account := range accounts {
		// The Matrix account itself has no bridge ghosts to match.
		if account.AccountID != matrixAccountID {
			lookup.ByBridge[account.AccountID] = append(lookup.ByBridge[account.AccountID], account)
		}
	}
	for bridgeID := range lookup.ByBridge {
		lookup.bridgeIDs = append(lookup.bridgeIDs, bridgeID)
	}
	sort.Slice(lookup.bridgeIDs, func(i, j int) bool {
		return len(lookup.bridgeIDs[i]) > len(lookup.bridgeIDs[j])
	})
	return lookup, nil
}

const matrixAccountID = "hungryserv"

// loadAccounts lists the Matrix account plus every running bridge login.
func (s *Dispatcher) loadAccounts(ctx context.Context) ([]compat.Account, error) {
	cli := s.rt.Client()
	if cli == nil || cli.Account == nil {
		return []compat.Account{}, nil
	}

	accountDataEvents, err := cli.DB.AccountData.GetAllGlobal(ctx, cli.Account.UserID)
	if err != nil {
		return nil, fmt.Errorf("failed to read global account data: %w", err)
	}

	var state bridgeStateContent
	for _, ad := range accountDataEvents {
		if ad.Type != bridgeStateEventType || len(ad.Content) == 0 {
			continue
		}
		if err = json.Unmarshal(ad.Content, &state); err != nil {
			return nil, fmt.Errorf("failed to parse %s: %w", bridgeStateEventType, err)
		}
		break
	}

	accounts := []compat.Account{{
		AccountID: matrixAccountID,
		Network:   "Beeper (Matrix)",
		User:      newUser(string(cli.Account.UserID), "", "", "", true),
	}}

	bridgeIDs := make([]string, 0, len(state.Bridges))
	for bridgeID := range state.Bridges {
		bridgeIDs = append(bridgeIDs, bridgeID)
	}
	sort.Strings(bridgeIDs)

	for _, bridgeID := range bridgeIDs {
		entry := state.Bridges[bridgeID]
		// Skip bridges that are not running.
		if strings.ToUpper(entry.BridgeState.StateEvent) != "RUNNING" {
			continue
		}
		remoteIDs := make([]string, 0, len(entry.RemoteState))
		for remoteID := range entry.RemoteState {
			remoteIDs = append(remoteIDs, remoteID)
		}
		sort.Strings(remoteIDs)

		for _, remoteID := range remoteIDs {
			remote := entry.RemoteState[remoteID]
			remoteState := strings.ToUpper(remote.StateEvent)
			if remoteState == "DELETED" || remoteState == "LOGGED_OUT" {
				continue
			}
			accounts = append(accounts, compat.Account{
				AccountID:    bridgeID,
				Network:      networkFromBridgeID(bridgeID),
				User:         userFromLocalBridgeProfile(remoteID, remote.RemoteProfile),
				Capabilities: capabilitiesForBridge(bridgeID),
			})
		}
	}
	return accounts, nil
}

func capabilitiesForBridge(bridgeID string) compat.AccountCapabilities {
	normalized := strings.TrimSuffix(strings.TrimPrefix(bridgeID, "local-"), "go")
	return compat.AccountCapabilities{
		UnlimitedMessageEdits: normalized == "telegram",
	}
}

type chatListInput struct {
	Query      string   `json:"query"`
	Inbox      string   `json:"inbox"`
	AccountIDs []string `json:"accountIDs"`
	// The last chat already shown; the page starts after it.
	BeforeTS     int64  `json:"beforeTS"`
	BeforeRoomID string `json:"beforeRoomID"`
}

func (s *Dispatcher) listChats(ctx context.Context, input json.RawMessage) (any, error) {
	var req chatListInput
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	return s.loadChatList(ctx, req, chatPageSize)
}

func (s *Dispatcher) searchChats(ctx context.Context, input json.RawMessage) (any, error) {
	var req chatListInput
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	return s.loadChatList(ctx, req, searchChatsLimit)
}

// loadChatList walks rooms newest first until it has a page of matches. Inbox
// and title filters run before the member and preview queries, so a search or
// an archive view doesn't summarize rooms it then discards.
func (s *Dispatcher) loadChatList(ctx context.Context, req chatListInput, limit int) (compat.ListChatsOutput, error) {
	lookup, err := s.buildAccountLookup(ctx)
	if err != nil {
		return compat.ListChatsOutput{}, err
	}
	inbox := strings.TrimSpace(req.Inbox)
	queryTokens := strings.Fields(strings.ToLower(req.Query))
	var position *roomPosition
	if req.BeforeTS > 0 {
		position = &roomPosition{ts: req.BeforeTS, roomID: req.BeforeRoomID}
	}

	items := make([]compat.Chat, 0, limit+1)
	for len(items) <= limit {
		rooms, loadErr := s.loadRoomPage(ctx, position)
		if loadErr != nil {
			return compat.ListChatsOutput{}, loadErr
		}
		if len(rooms) == 0 {
			break
		}
		last := rooms[len(rooms)-1]
		position = &roomPosition{ts: last.SortingTimestamp.UnixMilli(), roomID: string(last.ID)}

		ids := make([]id.RoomID, len(rooms))
		for i, room := range rooms {
			ids[i] = room.ID
		}
		states, loadErr := s.loadRoomAccountDataStates(ctx, ids...)
		if loadErr != nil {
			return compat.ListChatsOutput{}, loadErr
		}
		var candidates []*database.Room
		var candidateIDs []id.RoomID
		for _, room := range rooms {
			if roomMatchesInbox(room, states[room.ID], inbox) && titleMatches(roomTitle(room), queryTokens) {
				candidates = append(candidates, room)
				candidateIDs = append(candidateIDs, room.ID)
			}
		}
		if len(candidates) > 0 {
			reads, _ := s.loadLastReadSortKeys(ctx, candidateIDs...)
			summaries, loadErr := s.loadChatSummaries(ctx, candidates, chatPreviewParticipants, lookup)
			if loadErr != nil {
				return compat.ListChatsOutput{}, loadErr
			}
			for _, room := range candidates {
				if len(req.AccountIDs) > 0 && !slices.Contains(req.AccountIDs, lookup.roomAccounts[room.ID].accountID) {
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
	return compat.ListChatsOutput{Items: items, HasMore: hasMore}, nil
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
	chatID := strings.TrimSpace(req.ChatID)
	if chatID == "" {
		return nil, errors.New("chatID is required")
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

func (s *Dispatcher) loadRoomAccountDataStates(ctx context.Context, roomIDs ...id.RoomID) (map[id.RoomID]roomAccountDataState, error) {
	cli := s.rt.Client()
	if cli == nil || cli.Account == nil {
		return map[id.RoomID]roomAccountDataState{}, nil
	}
	query := roomAccountDataSelectQuery
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
		if scanErr := rows.Scan(&roomIDRaw, &eventType, &content); scanErr != nil {
			return nil, fmt.Errorf("failed to scan room account data: %w", scanErr)
		}
		if roomIDRaw == "" {
			continue
		}
		roomID := id.RoomID(roomIDRaw)
		states[roomID] = applyRoomAccountDataContent(states[roomID], eventType, content)
	}
	if err = rows.Err(); err != nil {
		return nil, fmt.Errorf("room account data query failed: %w", err)
	}
	return states, nil
}

// loadLastReadSortKeys returns the timeline position of the user's own read
// receipt in each room.
func (s *Dispatcher) loadLastReadSortKeys(ctx context.Context, roomIDs ...id.RoomID) (map[id.RoomID]string, error) {
	cli := s.rt.Client()
	if cli == nil || cli.Account == nil {
		return map[id.RoomID]string{}, nil
	}
	query := `
		SELECT r.room_id, t.rowid
		FROM receipt r
		JOIN event e ON e.event_id = r.event_id AND e.room_id = r.room_id
		JOIN timeline t ON t.event_rowid = e.rowid AND t.room_id = r.room_id
		WHERE r.user_id = ? AND r.receipt_type = 'm.read'
	`
	args := []any{cli.Account.UserID}
	if len(roomIDs) > 0 {
		query += " AND r.room_id IN (" + sqlSlots(len(roomIDs)) + ")"
		for _, roomID := range roomIDs {
			args = append(args, roomID)
		}
	}
	rows, err := cli.DB.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	result := make(map[id.RoomID]string)
	for rows.Next() {
		var roomIDRaw string
		var timelineRowID int64
		if scanErr := rows.Scan(&roomIDRaw, &timelineRowID); scanErr != nil {
			continue
		}
		if timelineRowID > 0 {
			result[id.RoomID(roomIDRaw)] = strconv.FormatInt(timelineRowID, 10)
		}
	}
	return result, rows.Err()
}

func roomTitle(room *database.Room) string {
	if room.Name != nil {
		if title := strings.TrimSpace(*room.Name); title != "" {
			return title
		}
	}
	return string(room.ID)
}

func (s *Dispatcher) mapRoomToChat(room *database.Room, summary *chatSummary, lookup *accountLookup, state roomAccountDataState, lastReadSortKey string) compat.Chat {
	chatType := "group"
	if room.DMUserID != nil && *room.DMUserID != "" {
		chatType = "single"
	}
	chat := compat.Chat{
		ID:        string(room.ID),
		AccountID: lookup.roomAccounts[room.ID].accountID,
		Title:     roomTitle(room),
		Type:      compat.ChatType(chatType),
		Participants: compat.Participants{
			Items:   summary.members,
			HasMore: summary.total > len(summary.members),
			Total:   int64(summary.total),
		},
		UnreadCount:            int64(room.UnreadMessages),
		IsArchived:             state.InArchive(),
		IsMuted:                state.IsMuted,
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
					read, _ := strconv.ParseInt(lastReadSortKey, 10, 64)
					sortKey, _ := strconv.ParseInt(preview.SortKey, 10, 64)
					preview.IsUnread = sortKey > read
				} else {
					preview.IsUnread = chat.UnreadCount > 0
				}
			}
			chat.Preview = &preview
		}
	}
	return chat
}

// inferAccountForRoom picks the account whose bridge ghosts are in the room,
// falling back to a bridge named in the room's server, then the Matrix account.
func inferAccountForRoom(roomID id.RoomID, members []compat.User, lookup *accountLookup) roomAccount {
	if len(lookup.Accounts) == 0 {
		return roomAccount{network: "Unknown"}
	}
	for _, member := range members {
		if member.IsSelf {
			continue
		}
		// Ghost user IDs look like @bridgeName_remoteID:server.
		localpart := strings.TrimPrefix(member.ID, "@")
		if index := strings.Index(localpart, ":"); index > 0 {
			localpart = localpart[:index]
		}
		for _, bridgeID := range lookup.bridgeIDs {
			if strings.HasPrefix(localpart, bridgeID+"_") {
				account := lookup.ByBridge[bridgeID][0]
				return roomAccount{accountID: account.AccountID, network: account.Network}
			}
		}
	}
	_, server, _ := strings.Cut(string(roomID), ":")
	for _, bridgeID := range lookup.bridgeIDs {
		if strings.Contains(server, bridgeID) {
			account := lookup.ByBridge[bridgeID][0]
			return roomAccount{accountID: account.AccountID, network: account.Network}
		}
	}
	fallback := lookup.Accounts[0]
	return roomAccount{accountID: fallback.AccountID, network: fallback.Network}
}

func firstString(m map[string]any, keys ...string) string {
	for _, key := range keys {
		if value, ok := m[key].(string); ok {
			if value = strings.TrimSpace(value); value != "" {
				return value
			}
		}
	}
	return ""
}

func networkFromBridgeID(bridgeID string) string {
	bridgeID = strings.TrimPrefix(bridgeID, "local-")
	switch bridgeID {
	case "whatsapp":
		return "WhatsApp"
	case "telegram":
		return "Telegram"
	case "twitter":
		return "Twitter/X"
	case "instagram", "instagramgo":
		return "Instagram"
	case "signal":
		return "Signal"
	case "linkedin":
		return "LinkedIn"
	case "discordgo", "discord":
		return "Discord"
	case "slackgo", "slack":
		return "Slack"
	case "facebookgo", "facebook":
		return "Facebook/Messenger"
	case "gmessages":
		return "Google Messages"
	case "gvoice":
		return "Google Voice"
	case "imessage", "imessagecloud":
		return "iMessage"
	default:
		if bridgeID == "" {
			return "Unknown"
		}
		return strings.ToUpper(bridgeID[:1]) + bridgeID[1:]
	}
}
