package dispatch

import (
	"context"
	"encoding/json"
	"strings"
	"time"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

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
	inThreads := threadTypers(cli.DB, update.RoomID, update.UserIDs)
	for _, userID := range update.UserIDs {
		localpart, _, _ := strings.Cut(strings.TrimPrefix(string(userID), "@"), ":")
		if userID == "" || userID == cli.Account.UserID || strings.HasSuffix(localpart, "bot") || seen[string(userID)] || inThreads[userID] {
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

const (
	// A Slack user whose last message within this window was a thread reply is
	// assumed to still be typing in that thread.
	threadTypingWindow = 10 * time.Minute
	// Bounds the lookup to the room's newest events, so a typist with no recent
	// message doesn't scan the whole room.
	threadTypingScanLimit = 500
)

// threadTypers guesses which Slack typists are typing in a thread. Slack's
// typing event names only the channel, and Matrix typing has no thread field,
// so the main timeline would otherwise show thread typing. A wrong guess only
// hides a bubble; the typist is never shown inside a thread.
func threadTypers(db *database.Database, roomID id.RoomID, userIDs []id.UserID) map[id.UserID]bool {
	var args []any
	for _, userID := range userIDs {
		if strings.HasPrefix(string(userID), "@slackgo_") {
			args = append(args, userID)
		}
	}
	if len(args) == 0 {
		return nil
	}
	cutoff := time.Now().Add(-threadTypingWindow).UnixMilli()
	// Reactions, edits and redactions don't say where the user is. Thread
	// replies also sent to the channel still count as thread activity.
	rows, err := db.Query(context.Background(), `SELECT sender, COALESCE(relation_type,'') FROM (
			SELECT sender, type, timestamp, redacted_by, relation_type FROM event
			WHERE room_id=? ORDER BY rowid DESC LIMIT ?)
		WHERE sender IN (`+sqlSlots(len(args))+`) AND timestamp>? AND redacted_by IS NULL
			AND type IN ('m.room.message','m.sticker','m.room.encrypted')
			AND COALESCE(relation_type,'') NOT IN ('m.replace','m.annotation')
		ORDER BY timestamp DESC`, append(append([]any{roomID, threadTypingScanLimit}, args...), cutoff)...)
	if err != nil {
		return nil
	}
	defer rows.Close()
	latest := make(map[id.UserID]bool)
	inThreads := make(map[id.UserID]bool)
	for rows.Next() {
		var sender id.UserID
		var relationType string
		if rows.Scan(&sender, &relationType) != nil || latest[sender] {
			continue
		}
		latest[sender] = true
		if relationType == string(event.RelThread) {
			inThreads[sender] = true
		}
	}
	return inThreads
}
