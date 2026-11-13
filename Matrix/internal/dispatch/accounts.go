package dispatch

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"sort"
	"strings"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

const (
	bridgeStateEventType = "com.beeper.bridge_state"
	// matrixAccountID identifies the Beeper Matrix account itself, as opposed
	// to a bridged network login.
	matrixAccountID = "hungryserv"
)

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
	RemoteName    string         `json:"remote_name"`
	RemoteProfile map[string]any `json:"remote_profile"`
	StateEvent    string         `json:"state_event"`
	Info          map[string]any `json:"info"`
}

// accountLookup assigns rooms to accounts by their bridge info, or by the
// bridge ghosts in them.
type accountLookup struct {
	accounts []wire.Account
	// Each bridge's logins, in bridge state order.
	byBridge map[string][]wire.Account
	// Bridge IDs longest first, so the most specific prefix matches.
	bridgeIDs []string
	// The account ID of each room summarized so far.
	roomAccounts map[id.RoomID]string
}

func (s *Dispatcher) getSession(ctx context.Context) (any, error) {
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

	// Logos and workspaces are only shown, so a failure leaves them out.
	_ = s.fillNetworkDetails(ctx, accounts)
	return wire.SessionOutput{User: user, Accounts: accounts}, nil
}

func (s *Dispatcher) buildAccountLookup(ctx context.Context) (*accountLookup, error) {
	accounts, err := s.loadAccounts(ctx)
	if err != nil {
		return nil, err
	}
	lookup := &accountLookup{
		accounts:     accounts,
		byBridge:     make(map[string][]wire.Account),
		roomAccounts: make(map[id.RoomID]string),
	}
	for _, account := range accounts {
		// The Matrix account itself has no bridge ghosts to match. Logins
		// group under their bridge, which ghost localparts and m.bridge
		// protocol IDs name; account IDs add the login's remote ID.
		if account.BridgeID != matrixAccountID {
			lookup.byBridge[account.BridgeID] = append(lookup.byBridge[account.BridgeID], account)
		}
	}
	for bridgeID := range lookup.byBridge {
		lookup.bridgeIDs = append(lookup.bridgeIDs, bridgeID)
	}
	sort.Slice(lookup.bridgeIDs, func(i, j int) bool {
		return len(lookup.bridgeIDs[i]) > len(lookup.bridgeIDs[j])
	})
	return lookup, nil
}

// loadAccounts lists the Matrix account plus every running bridge login.
func (s *Dispatcher) loadAccounts(ctx context.Context) ([]wire.Account, error) {
	cli := s.rt.Client()
	if cli == nil || cli.Account == nil {
		return []wire.Account{}, nil
	}

	// This runs for every sync batch and chat list page. Read only the bridge
	// state, not all global account data (m.direct and push rules can be
	// large), and parse it only when it changed.
	var content []byte
	err := cli.DB.QueryRow(ctx, `SELECT content FROM account_data WHERE user_id = ? AND type = ?`,
		cli.Account.UserID, bridgeStateEventType).Scan(&content)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return nil, fmt.Errorf("failed to read %s: %w", bridgeStateEventType, err)
	}
	if cached, ok := s.accountsCache.get(cli.Account.UserID, content); ok {
		return cached, nil
	}

	var state bridgeStateContent
	if len(content) > 0 {
		if err = json.Unmarshal(content, &state); err != nil {
			return nil, fmt.Errorf("failed to parse %s: %w", bridgeStateEventType, err)
		}
	}

	accounts := []wire.Account{{
		AccountID: matrixAccountID,
		BridgeID:  matrixAccountID,
		Network:   "Beeper",
		User:      newUser(string(cli.Account.UserID), "", "", "", true),
	}}

	for _, bridgeID := range sortedMapKeys(state.Bridges) {
		entry := state.Bridges[bridgeID]
		// Skip bridges that are not running.
		if strings.ToUpper(entry.BridgeState.StateEvent) != "RUNNING" {
			continue
		}
		for _, remoteID := range sortedMapKeys(entry.RemoteState) {
			remote := entry.RemoteState[remoteID]
			remoteState := strings.ToUpper(remote.StateEvent)
			if remoteState == "DELETED" || remoteState == "LOGGED_OUT" {
				continue
			}
			account := wire.Account{
				AccountID:    loginAccountID(bridgeID, remoteID),
				BridgeID:     bridgeID,
				Network:      networkFromBridgeID(bridgeID),
				LoginName:    strings.TrimSpace(remote.RemoteName),
				User:         userFromBridgeProfile(remoteID, remote.RemoteProfile),
				Capabilities: capabilitiesForBridge(bridgeID),
			}
			if teamID := firstString(remote.Info, "slack_team_id"); teamID != "" {
				account.Workspace = &wire.Workspace{ID: teamID, Name: workspaceName(remote.RemoteName)}
			}
			accounts = append(accounts, account)
		}
	}
	s.accountsCache.set(cli.Account.UserID, content, accounts)
	return slices.Clone(accounts), nil
}

// loginAccountID identifies one login on a bridge. Remote IDs are unique only
// within their bridge.
func loginAccountID(bridgeID, remoteID string) string {
	return bridgeID + "/" + remoteID
}

// workspaceName is the team in a Slack login's remote name, which reads
// "Team - email".
func workspaceName(remoteName string) string {
	name, _, _ := strings.Cut(remoteName, " - ")
	return strings.TrimSpace(name)
}

func sortedMapKeys[Value any](values map[string]Value) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func capabilitiesForBridge(bridgeID string) wire.AccountCapabilities {
	normalized := strings.TrimSuffix(strings.TrimPrefix(bridgeID, "local-"), "go")
	return wire.AccountCapabilities{
		UnlimitedMessageEdits: normalized == "telegram",
		Threads:               normalized == "slack",
	}
}

// inferAccountForRoom picks the login the room's bridge info names, falling
// back to the bridge whose ghosts are in the room, then a bridge named in the
// room's server, then the Matrix account.
func inferAccountForRoom(roomID id.RoomID, members []wire.User, bridges []roomBridge, lookup *accountLookup) string {
	if len(lookup.accounts) == 0 {
		return ""
	}
	receiver := ""
	for _, bridge := range bridges {
		if logins := lookup.byBridge[bridge.protocolID]; len(logins) > 0 {
			return loginForReceiver(logins, bridge.receiver)
		}
		if receiver == "" {
			receiver = bridge.receiver
		}
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
				return loginForReceiver(lookup.byBridge[bridgeID], receiver)
			}
		}
	}
	_, server, _ := strings.Cut(string(roomID), ":")
	for _, bridgeID := range lookup.bridgeIDs {
		if strings.Contains(server, bridgeID) {
			return loginForReceiver(lookup.byBridge[bridgeID], receiver)
		}
	}
	return lookup.accounts[0].AccountID
}

// loginForReceiver picks the bridge login whose remote ID is the room's
// receiver. A room without one, such as a Discord server channel several
// logins share, goes to the bridge's first login.
func loginForReceiver(logins []wire.Account, receiver string) string {
	if receiver != "" {
		for _, login := range logins {
			if login.User.ID == receiver {
				return login.AccountID
			}
		}
	}
	return logins[0].AccountID
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
		return "Facebook"
	case "gmessages":
		return "Google Messages"
	case "gvoice":
		return "Google Voice"
	case "imessage", "imessagecloud":
		return "iMessage"
	case "wechat":
		return "WeChat"
	case "chatgpt-dots":
		return "ChatGPT"
	case "":
		return "Unknown"
	default:
		return strings.ToUpper(bridgeID[:1]) + bridgeID[1:]
	}
}

// newUser trims every field and falls back to the user ID for a missing name.
func newUser(userID, fullName, imgURL, username string, isSelf bool) wire.User {
	userID = strings.TrimSpace(userID)
	fullName = strings.TrimSpace(fullName)
	if fullName == "" {
		fullName = userID
	}
	return wire.User{
		ID:       userID,
		Username: strings.TrimSpace(username),
		FullName: fullName,
		ImgURL:   strings.TrimSpace(imgURL),
		IsSelf:   isSelf,
	}
}

func userFromBridgeProfile(remoteID string, profile map[string]any) wire.User {
	return newUser(
		remoteID,
		firstString(profile, "name", "display_name", "displayName"),
		firstString(profile, "avatar", "avatar_url"),
		firstString(profile, "username", "handle"),
		true,
	)
}

func userFromMemberEvent(userID string, member event.MemberEventContent, selfUserID string) wire.User {
	return newUser(userID, member.Displayname, string(member.AvatarURL), "", userID == selfUserID)
}

// firstString returns the first non-empty string value among keys.
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
