package dispatch

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/compat"
	"relay/core/internal/cursor"
	errs "relay/core/internal/errors"
)

const (
	bridgeStateEventType    = "com.beeper.bridge_state"
	chatPageSize            = 25
	chatPreviewParticipants = 5
)

const roomSelectBaseQuery = `
	SELECT room_id, creation_content, tombstone_content, name, name_quality,
	       avatar, explicit_avatar, dm_user_id, topic, canonical_alias,
	       lazy_load_summary, encryption_event, has_member_list, preview_event_rowid, sorting_timestamp,
	       unread_highlights, unread_notifications, unread_messages, marked_unread, prev_batch
	FROM room
`

const roomSelectSortedQuery = roomSelectBaseQuery + `WHERE sorting_timestamp > 0 AND room_type<>'m.space' ORDER BY sorting_timestamp DESC, room_id ASC`
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
	RemoteID      string         `json:"remote_id"`
	RemoteName    string         `json:"remote_name"`
	RemoteProfile map[string]any `json:"remote_profile"`
	StateEvent    string         `json:"state_event"`
}

type roomAccount struct{ accountID, network string }

type accountLookup struct {
	roomAccounts map[id.RoomID]roomAccount
	Accounts     []compat.Account
	ByID         map[string]compat.Account
	ByBridge     map[string][]compat.Account
}

type roomAccountDataState struct {
	IsMuted               bool
	MutedUntil            int64
	IsPinned              bool
	IsLowPriority         bool
	IsMarkedUnread        bool
	MarkedUnreadUpdatedAt int64
	ArchivedUpdatedTS     *int64
	ArchivedAtOrder       *int64
	SnoozeUntilMS         *int64
	UserSnoozedAt         *int64
}

type beeperInboxDoneContent struct {
	UpdatedTS *int64 `json:"updated_ts,omitempty"`
	AtOrder   *int64 `json:"at_order,omitempty"`
}

type markedUnreadContent struct {
	Unread bool  `json:"unread"`
	TS     int64 `json:"ts,omitempty"`
}

type snoozedContent struct {
	SnoozedUntilMS *int64 `json:"snoozed_until_ms,omitempty"`
	UserSnoozedAt  *int64 `json:"user_snoozed_at,omitempty"`
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
		_, state.IsPinned = tags.Tags[event.RoomTagFavourite]
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
	case "com.beeper.chats.snoozed":
		var snoozed snoozedContent
		if unmarshalErr := json.Unmarshal(content, &snoozed); unmarshalErr != nil {
			return state
		}
		state.SnoozeUntilMS = snoozed.SnoozedUntilMS
		state.UserSnoozedAt = snoozed.UserSnoozedAt
	case "com.famedly.marked_unread":
		// Ignored in Beeper Desktop as well.
	}
	return state
}

func (s *Dispatcher) getAccounts(w http.ResponseWriter, r *http.Request) error {
	accounts, err := s.loadAccounts(r.Context())
	if err != nil {
		return err
	}
	return writeJSON(w, accounts)
}

func (s *Dispatcher) getSession(w http.ResponseWriter, r *http.Request) error {
	accounts, err := s.loadAccounts(r.Context())
	if err != nil {
		return err
	}

	cli := s.rt.Client()
	user := newCompatUser(userShape{ID: string(cli.Account.UserID), IsSelf: true})
	for _, account := range accounts {
		if account.User.IsSelf && account.User.FullName != "" && account.User.FullName != account.User.ID {
			user = account.User
			break
		}
	}
	if profile, profileErr := cli.Client.GetProfile(r.Context(), cli.Account.UserID); profileErr == nil && profile != nil &&
		(strings.TrimSpace(profile.DisplayName) != "" || !profile.AvatarURL.IsEmpty()) {
		user = newCompatUser(userShape{
			ID:       string(cli.Account.UserID),
			FullName: profile.DisplayName,
			ImgURL:   profile.AvatarURL.String(),
			IsSelf:   true,
		})
	}

	return writeJSON(w, compat.SessionOutput{User: user, Accounts: accounts})
}

func (s *Dispatcher) buildAccountLookup(ctx context.Context) (*accountLookup, error) {
	accounts, err := s.loadAccounts(ctx)
	if err != nil {
		return nil, err
	}
	lookup := &accountLookup{
		Accounts: accounts,
		ByID:     make(map[string]compat.Account, len(accounts)),
		ByBridge: make(map[string][]compat.Account),
	}
	for _, account := range accounts {
		lookup.ByID[account.AccountID] = account
		bridgeID := bridgeIDFromAccountID(account.AccountID)
		if bridgeID != "" {
			lookup.ByBridge[bridgeID] = append(lookup.ByBridge[bridgeID], account)
		}
	}
	return lookup, nil
}

func (s *Dispatcher) loadAccounts(ctx context.Context) ([]compat.Account, error) {
	cli := s.rt.Client()
	if cli == nil || cli.Account == nil {
		return []compat.Account{}, nil
	}

	accountDataEvents, err := cli.DB.AccountData.GetAllGlobal(ctx, cli.Account.UserID)
	if err != nil {
		return nil, errs.Internal(fmt.Errorf("failed to read global account data: %w", err))
	}

	var state bridgeStateContent
	for _, ad := range accountDataEvents {
		if ad.Type != bridgeStateEventType {
			continue
		}
		if len(ad.Content) == 0 {
			continue
		}
		if err = json.Unmarshal(ad.Content, &state); err != nil {
			return nil, errs.Internal(fmt.Errorf("failed to parse %s: %w", bridgeStateEventType, err))
		}
		break
	}

	accounts := make([]compat.Account, 0)

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
			remoteStateUpper := strings.ToUpper(remote.StateEvent)
			if remoteStateUpper == "DELETED" || remoteStateUpper == "LOGGED_OUT" {
				continue
			}

			network := networkFromBridgeID(bridgeID)
			accounts = append(accounts, compat.Account{
				AccountID: bridgeID,
				Network:   network,
				User:      userFromLocalBridgeProfile(remoteID, remote.RemoteProfile),
			})
		}
	}

	// Also add the matrix account itself as "hungryserv".
	matrixUser := newCompatUser(userShape{ID: string(cli.Account.UserID), IsSelf: true})
	// Try to get the display name from the profile.
	if profile, profileErr := cli.DB.CurrentState.Get(ctx, id.RoomID(""), event.StateRoomName, ""); profileErr == nil && profile != nil {
		_ = profile // Not needed for global profile.
	}
	accounts = append([]compat.Account{{
		AccountID: "hungryserv",
		Network:   "Beeper (Matrix)",
		User:      matrixUser,
	}}, accounts...)

	if len(accounts) == 0 {
		accounts = append(accounts, compat.Account{
			AccountID: "matrix_" + string(cli.Account.UserID),
			Network:   "Matrix",
			User:      newCompatUser(userShape{ID: string(cli.Account.UserID), IsSelf: true}),
		})
	}

	for index := range accounts {
		networkID := bridgeIDFromAccountID(accounts[index].AccountID)
		if networkID == "" {
			networkID = "matrix"
		}
		accounts[index].NetworkID = networkID
		accounts[index].Capabilities = capabilitiesForNetwork(networkID)
	}

	return accounts, nil
}

func capabilitiesForNetwork(networkID string) compat.AccountCapabilities {
	normalized := strings.TrimSuffix(strings.TrimPrefix(networkID, "local-"), "go")
	return compat.AccountCapabilities{
		UnlimitedMessageEdits: normalized == "telegram",
	}
}

func bridgeIDFromAccountID(accountID string) string {
	// Account IDs are now the bridge name directly (e.g., "whatsapp", "discordgo").
	// The hungryserv account is the Matrix account itself.
	if accountID == "hungryserv" || accountID == "" {
		return ""
	}
	return accountID
}

func (s *Dispatcher) listChats(w http.ResponseWriter, r *http.Request) error {
	lookup, err := s.buildAccountLookup(r.Context())
	if err != nil {
		return err
	}
	direction, err := parseDirection(r.URL.Query().Get("direction"))
	if err != nil {
		return err
	}
	cursorValue, err := parseChatCursor(r.URL.Query().Get("cursor"))
	if err != nil {
		return err
	}
	accountIDs := parseAccountIDs(r)
	inbox := strings.TrimSpace(r.URL.Query().Get("inbox"))
	items := make([]compat.Chat, 0, chatPageSize+1)
	var scanned *cursor.ChatCursor
	for len(items) <= chatPageSize {
		rooms, loadErr := s.loadRoomPage(r.Context(), cursorValue, direction, scanned)
		if loadErr != nil {
			return loadErr
		}
		if len(rooms) == 0 {
			break
		}
		ids := make([]id.RoomID, len(rooms))
		for i, room := range rooms {
			ids[i] = room.ID
		}
		states, loadErr := s.loadRoomAccountDataStates(r.Context(), ids...)
		if loadErr != nil {
			return loadErr
		}
		reads, _ := s.loadLastReadSortKeys(r.Context(), ids...)
		summaries, loadErr := s.loadChatSummaries(r.Context(), rooms, chatPreviewParticipants, lookup, true)
		if loadErr != nil {
			return loadErr
		}
		ctx := context.WithValue(r.Context(), chatSummaryKey{}, summaries)
		for _, room := range rooms {
			state := states[room.ID]
			if !roomMatchesInbox(room, state, inbox) {
				continue
			}
			chat, mapErr := s.mapRoomToChat(ctx, room, lookup, chatPreviewParticipants, true, state, reads[room.ID])
			if mapErr != nil {
				return mapErr
			}
			if len(accountIDs) > 0 && !equalsAny(chat.AccountID, accountIDs) {
				continue
			}
			items = append(items, chat)
			if len(items) > chatPageSize {
				break
			}
		}
		last := rooms[len(rooms)-1]
		scanned = &cursor.ChatCursor{TS: last.SortingTimestamp.UnixMilli(), RoomID: string(last.ID)}
		if len(rooms) < chatPageSize+1 {
			break
		}
	}

	hasMore := len(items) > chatPageSize
	if hasMore {
		items = items[:chatPageSize]
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

	return writeJSON(w, compat.ListChatsOutput{
		Items:        items,
		HasMore:      hasMore,
		OldestCursor: oldestCursor,
		NewestCursor: newestCursor,
	})
}

func (s *Dispatcher) getChat(w http.ResponseWriter, r *http.Request) error {
	chatID := readChatID(r, "")
	if chatID == "" {
		return errs.Validation(map[string]any{"chatID": "chatID is required"})
	}
	maxParticipants, err := parseParticipantLimit(r.URL.Query().Get("maxParticipantCount"))
	if err != nil {
		return err
	}
	lookup, err := s.buildAccountLookup(r.Context())
	if err != nil {
		return err
	}
	cli := s.rt.Client()
	room, err := cli.DB.Room.Get(r.Context(), id.RoomID(chatID))
	if err != nil {
		return errs.Internal(fmt.Errorf("failed to read room metadata: %w", err))
	}
	if room == nil {
		return errs.NotFound("Chat not found")
	}
	roomStates, err := s.loadRoomAccountDataStates(r.Context(), room.ID)
	if err != nil {
		return err
	}
	lastReadKey := s.loadLastReadSortKey(r.Context(), room.ID)
	chat, err := s.mapRoomToChat(r.Context(), room, lookup, maxParticipants, true, roomStates[room.ID], lastReadKey)
	if err != nil {
		return err
	}
	return writeJSON(w, chat)
}

func (s *Dispatcher) loadRoomsSorted(ctx context.Context) ([]*database.Room, error) {
	cli := s.rt.Client()
	rows, err := cli.DB.Query(ctx, roomSelectSortedQuery)
	if err != nil {
		return nil, errs.Internal(fmt.Errorf("failed to query rooms: %w", err))
	}
	defer rows.Close()

	rooms := make([]*database.Room, 0)
	for rows.Next() {
		room := &database.Room{}
		if _, scanErr := room.Scan(rows); scanErr != nil {
			return nil, errs.Internal(fmt.Errorf("failed to scan room: %w", scanErr))
		}
		rooms = append(rooms, room)
	}
	if err = rows.Err(); err != nil {
		return nil, errs.Internal(fmt.Errorf("room query failed: %w", err))
	}
	return rooms, nil
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
		return nil, errs.Internal(fmt.Errorf("failed to query room account data: %w", err))
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
			return nil, errs.Internal(fmt.Errorf("failed to scan room account data: %w", scanErr))
		}
		if roomIDRaw == "" {
			continue
		}
		roomID := id.RoomID(roomIDRaw)
		state := states[roomID]
		states[roomID] = applyRoomAccountDataContent(state, eventType, content)
	}
	if err = rows.Err(); err != nil {
		return nil, errs.Internal(fmt.Errorf("room account data query failed: %w", err))
	}
	return states, nil
}

const readReceiptQuery = `SELECT event_id FROM receipt WHERE room_id = ? AND user_id = ? AND receipt_type = 'm.read' LIMIT 1`
const timelineRowIDForEventQuery = `SELECT timeline.rowid FROM timeline JOIN event ON event.rowid = timeline.event_rowid WHERE timeline.room_id = ? AND event.event_id = ? LIMIT 1`

// loadLastReadSortKey returns the timeline rowid of the self-user's last read receipt for a room.
func (s *Dispatcher) loadLastReadSortKey(ctx context.Context, roomID id.RoomID) string {
	cli := s.rt.Client()
	if cli == nil || cli.Account == nil {
		return ""
	}
	var eventID string
	err := cli.DB.QueryRow(ctx, readReceiptQuery, roomID, cli.Account.UserID).Scan(&eventID)
	if err != nil || eventID == "" {
		return ""
	}
	var timelineRowID int64
	err = cli.DB.QueryRow(ctx, timelineRowIDForEventQuery, roomID, eventID).Scan(&timelineRowID)
	if err != nil || timelineRowID <= 0 {
		return ""
	}
	return strconv.FormatInt(timelineRowID, 10)
}

// loadLastReadSortKeys loads read receipt sort keys for all rooms at once.
func (s *Dispatcher) loadLastReadSortKeys(ctx context.Context, roomIDs ...id.RoomID) (map[id.RoomID]string, error) {
	cli := s.rt.Client()
	if cli == nil || cli.Account == nil {
		return map[id.RoomID]string{}, nil
	}
	const batchQuery = `
		SELECT r.room_id, t.rowid
		FROM receipt r
		JOIN event e ON e.event_id = r.event_id AND e.room_id = r.room_id
		JOIN timeline t ON t.event_rowid = e.rowid AND t.room_id = r.room_id
		WHERE r.user_id = ? AND r.receipt_type = 'm.read'
	`
	query := batchQuery
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

func roomIsOlderThanCursor(room *database.Room, c *cursor.ChatCursor) bool {
	ts := room.SortingTimestamp.UnixMilli()
	if ts < c.TS {
		return true
	}
	if ts > c.TS {
		return false
	}
	if c.RoomID == "" {
		return false
	}
	return string(room.ID) > c.RoomID
}

func roomIsNewerThanCursor(room *database.Room, c *cursor.ChatCursor) bool {
	ts := room.SortingTimestamp.UnixMilli()
	if ts > c.TS {
		return true
	}
	if ts < c.TS {
		return false
	}
	if c.RoomID == "" {
		return false
	}
	return string(room.ID) < c.RoomID
}

func (s *Dispatcher) mapRoomToChat(ctx context.Context, room *database.Room, lookup *accountLookup, maxParticipants int, includePreview bool, roomState roomAccountDataState, lastReadSortKey ...string) (compat.Chat, error) {
	accountID, network := inferAccountForRoom(room.ID, lookup)
	summaries, _ := ctx.Value(chatSummaryKey{}).(map[id.RoomID]*chatSummary)
	summary := summaries[room.ID]
	if summary == nil {
		var err error
		summaries, err = s.loadChatSummaries(ctx, []*database.Room{room}, maxParticipants, lookup, includePreview)
		if err != nil {
			return compat.Chat{}, err
		}
		summary = summaries[room.ID]
	}
	participants, total := summary.members, summary.total
	if memberAccountID, memberNetwork, ok := inferAccountFromMembers(summary.accountMembers, string(s.rt.Client().Account.UserID), lookup); ok {
		accountID, network = memberAccountID, memberNetwork
	}

	filteredParticipants := participants
	hasMoreParticipants := total > len(filteredParticipants)
	if maxParticipants >= 0 && len(filteredParticipants) > maxParticipants {
		filteredParticipants = filteredParticipants[:maxParticipants]
		hasMoreParticipants = true
	}

	title := strings.TrimSpace(ptrString(room.Name))
	if title == "" {
		title = string(room.ID)
	}
	chatType := "group"
	if room.DMUserID != nil && *room.DMUserID != "" {
		chatType = "single"
	}

	chat := compat.Chat{Network: network}
	chat.ID = string(room.ID)
	chat.AccountID = accountID
	chat.Title = title
	chat.Type = compat.ChatType(chatType)
	if room.Avatar != nil {
		if avatarURL := room.Avatar.String(); avatarURL != "" && avatarURL != "mxc://" {
			chat.ImgURL = avatarURL
		}
	}
	chat.Participants = compat.Participants{
		Items:   filteredParticipants,
		HasMore: hasMoreParticipants,
		Total:   int64(total),
	}
	chat.UnreadCount = int64(room.UnreadMessages)
	chat.IsArchived = roomState.InArchive()
	chat.IsMuted = roomState.IsMuted
	chat.IsPinned = roomState.IsPinned
	chat.IsMarkedUnread = roomState.IsMarkedUnread
	if roomState.MarkedUnreadUpdatedAt > 0 {
		chat.Extra = &compat.ChatExtra{
			MarkedUnreadUpdatedAt: roomState.MarkedUnreadUpdatedAt,
		}
	}
	if roomState.SnoozeUntilMS != nil || roomState.UserSnoozedAt != nil {
		chat.Snooze = &compat.ChatSnooze{
			SnoozeUntilMS: roomState.SnoozeUntilMS,
			UserSnoozedAt: roomState.UserSnoozedAt,
		}
	}

	if ts := room.SortingTimestamp.UnixMilli(); ts > 0 {
		chat.LastActivity = time.UnixMilli(ts).UTC()
	}

	// Set localChatID to room ID (matches reference server behavior).
	chat.LocalChatID = string(room.ID)

	// Set lastReadMessageSortKey from read receipts.
	if len(lastReadSortKey) > 0 && lastReadSortKey[0] != "" {
		chat.LastReadMessageSortKey = lastReadSortKey[0]
	}

	if includePreview && summary.preview != nil {
		if preview, err := s.mapEventToMessage(ctx, summary.preview, room, lookup, reactionBundle{Names: summary.names}); err == nil {
			if !preview.IsSender {
				if chat.LastReadMessageSortKey != "" {
					read, _ := strconv.ParseInt(chat.LastReadMessageSortKey, 10, 64)
					preview.IsUnread = previewNumericKey(preview) > read
				} else {
					preview.IsUnread = chat.UnreadCount > 0
				}
			}
			chat.Preview = &preview
		}
	}

	return chat, nil
}

func inferAccountForRoom(roomID id.RoomID, lookup *accountLookup) (string, string) {
	if lookup == nil || len(lookup.Accounts) == 0 {
		return "", "Unknown"
	}
	server := roomServerPart(string(roomID))
	bridgeIDs := make([]string, 0, len(lookup.ByBridge))
	for bridgeID := range lookup.ByBridge {
		bridgeIDs = append(bridgeIDs, bridgeID)
	}
	// Sort longest first for best match.
	sort.Slice(bridgeIDs, func(i, j int) bool {
		return len(bridgeIDs[i]) > len(bridgeIDs[j])
	})

	for _, bridgeID := range bridgeIDs {
		if strings.Contains(server, bridgeID) {
			accounts := lookup.ByBridge[bridgeID]
			if len(accounts) > 0 {
				return accounts[0].AccountID, accounts[0].Network
			}
		}
	}

	// If not matched by server part, store roomID for member-based inference
	// (done in mapRoomToChat after loading participants).
	fallback := lookup.Accounts[0]
	return fallback.AccountID, fallback.Network
}

// inferAccountFromMembers inspects room member user IDs to determine the bridge.
// Bridge ghost user IDs follow the pattern @<bridgeName>_<remoteID>:<server>.
func inferAccountFromMembers(participants []compat.User, selfUserID string, lookup *accountLookup) (string, string, bool) {
	if lookup == nil {
		return "", "", false
	}
	bridgeIDs := make([]string, 0, len(lookup.ByBridge))
	for bridgeID := range lookup.ByBridge {
		bridgeIDs = append(bridgeIDs, bridgeID)
	}
	// Sort longest first for best match.
	sort.Slice(bridgeIDs, func(i, j int) bool {
		return len(bridgeIDs[i]) > len(bridgeIDs[j])
	})

	for _, p := range participants {
		if p.ID == selfUserID || p.IsSelf {
			continue
		}
		// Ghost user IDs: @bridgeName_remoteID:server
		localpart := p.ID
		if strings.HasPrefix(localpart, "@") {
			localpart = localpart[1:]
		}
		if idx := strings.Index(localpart, ":"); idx > 0 {
			localpart = localpart[:idx]
		}
		for _, bridgeID := range bridgeIDs {
			if strings.HasPrefix(localpart, bridgeID+"_") {
				accounts := lookup.ByBridge[bridgeID]
				if len(accounts) > 0 {
					return accounts[0].AccountID, accounts[0].Network, true
				}
			}
		}
	}
	return "", "", false
}

// isBridgeBot returns true if the user ID looks like a bridge bot (e.g., @whatsappbot:beeper.local).
func isBridgeBot(userID string) bool {
	localpart := userID
	if strings.HasPrefix(localpart, "@") {
		localpart = localpart[1:]
	}
	if idx := strings.Index(localpart, ":"); idx > 0 {
		localpart = localpart[:idx]
	}
	return strings.HasSuffix(localpart, "bot")
}

func roomServerPart(roomID string) string {
	parts := strings.SplitN(roomID, ":", 2)
	if len(parts) != 2 {
		return ""
	}
	return parts[1]
}

func ptrString(value *string) string {
	if value == nil {
		return ""
	}
	return *value
}

func firstString(m map[string]any, keys ...string) string {
	for _, key := range keys {
		value, ok := m[key]
		if !ok {
			continue
		}
		if s, ok := value.(string); ok {
			s = strings.TrimSpace(s)
			if s != "" {
				return s
			}
		}
	}
	return ""
}

func mustParseRFC3339(raw time.Time) int64 {
	if raw.IsZero() {
		return 0
	}
	return raw.UnixMilli()
}

func networkFromBridgeID(bridgeID string) string {
	if strings.HasPrefix(bridgeID, "local-") {
		bridgeID = strings.TrimPrefix(bridgeID, "local-")
	}
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
