package dispatch

import (
	"context"
	"encoding/json"
	"strings"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
	"maunium.net/go/mautrix/event"

	"relay/core/internal/wire"
)

// Typing is receive-only. Resolve names from local membership, without sending
// a typing request or fetching profiles from the homeserver.
func (h *eventHub) processTyping(update *jsoncmd.Typing) {
	cli := h.dispatcher.rt.Client()
	if update == nil || cli == nil || cli.Account == nil || !h.isWatching(string(update.RoomID), true) {
		return
	}
	users := make([]wire.User, 0, len(update.UserIDs))
	keys := make([]database.RoomStateGUID, 0, len(update.UserIDs))
	seen := make(map[string]bool)
	for _, userID := range update.UserIDs {
		localpart, _, _ := strings.Cut(strings.TrimPrefix(string(userID), "@"), ":")
		if userID == "" || userID == cli.Account.UserID || strings.HasSuffix(localpart, "bot") || seen[string(userID)] {
			continue
		}
		seen[string(userID)] = true
		users = append(users, newUser(string(userID), "", "", "", false))
		keys = append(keys, database.RoomStateGUID{RoomID: update.RoomID, Type: event.StateMember, StateKey: string(userID)})
	}
	if len(keys) > 0 {
		members, _ := cli.DB.CurrentState.GetMany(context.Background(), keys)
		byID := make(map[string]wire.User, len(members))
		for _, member := range members {
			var content event.MemberEventContent
			if member.StateKey != nil && json.Unmarshal(member.GetContent(), &content) == nil {
				byID[*member.StateKey] = userFromMemberEvent(*member.StateKey, content, string(cli.Account.UserID))
			}
		}
		for index, user := range users {
			if member, ok := byID[user.ID]; ok {
				users[index] = member
			}
		}
	}
	// An empty list clears the previous state, including self-only updates.
	sendChange(h, realtimeTypeTypingUpdated, string(update.RoomID), users)
}
