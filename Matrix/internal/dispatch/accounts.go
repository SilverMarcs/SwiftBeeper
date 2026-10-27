package dispatch

import (
	"context"
	"encoding/json"
	"fmt"
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
	RemoteProfile map[string]any `json:"remote_profile"`
	StateEvent    string         `json:"state_event"`
}

// accountLookup assigns rooms to accounts by the bridge ghosts in them.
type accountLookup struct {
	accounts []wire.Account
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
		// The Matrix account itself has no bridge ghosts to match.
		if account.AccountID != matrixAccountID {
			lookup.byBridge[account.AccountID] = append(lookup.byBridge[account.AccountID], account)
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

	accounts := []wire.Account{{
		AccountID: matrixAccountID,
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
			accounts = append(accounts, wire.Account{
				AccountID:    bridgeID,
				Network:      networkFromBridgeID(bridgeID),
				User:         userFromBridgeProfile(remoteID, remote.RemoteProfile),
				Capabilities: capabilitiesForBridge(bridgeID),
			})
		}
	}
	return accounts, nil
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
	}
}

// inferAccountForRoom picks the account whose bridge ghosts are in the room,
// falling back to a bridge named in the room's server, then the Matrix account.
func inferAccountForRoom(roomID id.RoomID, members []wire.User, lookup *accountLookup) string {
	if len(lookup.accounts) == 0 {
		return ""
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
				return lookup.byBridge[bridgeID][0].AccountID
			}
		}
	}
	_, server, _ := strings.Cut(string(roomID), ":")
	for _, bridgeID := range lookup.bridgeIDs {
		if strings.Contains(server, bridgeID) {
			return lookup.byBridge[bridgeID][0].AccountID
		}
	}
	return lookup.accounts[0].AccountID
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
