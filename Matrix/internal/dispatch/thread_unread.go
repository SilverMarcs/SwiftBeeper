package dispatch

import (
	"cmp"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"maps"
	"slices"
	"time"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

// A thread is unread while it has a reply that notified you, one in a thread
// you started or follow or that mentions you, newer than your read receipt in
// that thread and than when you last marked it as read. Replying in a thread
// reads it, since the server moves your receipt there to your reply. What you
// send or read in the main conversation leaves threads as they were, as in
// Slack; only marking the whole chat as read clears them all. When you last
// read each thread lives in room account data, so every device clears the
// same threads, and nothing reaches the network bridged behind the chat the
// way a read receipt would.

var threadSeenType = event.Type{Type: RelayRulePrefix + "thread_seen", Class: event.AccountDataEventType}

const (
	// Older replies never mark a thread unread, which also bounds the scan.
	threadUnreadWindow = 14 * 24 * time.Hour
	// Opened threads are remembered this long, beyond any reply that counts.
	threadSeenRetention = 30 * 24 * time.Hour
	unreadThreadLimit   = 20
)

type threadSeenContent struct {
	// When you last marked each thread as read, by root event ID, in Unix milliseconds.
	Roots map[id.EventID]int64 `json:"roots"`
	// When you last marked the whole chat as read, which reads every thread.
	All int64 `json:"all,omitempty"`
}

// isAlertingThreadReply reports whether evt is someone else's thread reply
// that notified you.
func isAlertingThreadReply(evt *database.Event, me id.UserID) bool {
	return isHiddenThreadReply(evt) && evt.Sender != me && evt.UnreadType.Is(database.UnreadTypeNotify)
}

func (s *Dispatcher) loadThreadSeen(ctx context.Context, roomID id.RoomID) (threadSeenContent, error) {
	cli := s.rt.Client()
	var content threadSeenContent
	var raw []byte
	err := cli.DB.QueryRow(ctx, `SELECT content FROM room_account_data WHERE user_id=? AND room_id=? AND type=?`,
		cli.Account.UserID, roomID, threadSeenType.Type).Scan(&raw)
	if errors.Is(err, sql.ErrNoRows) {
		return content, nil
	} else if err != nil {
		return content, err
	}
	return content, json.Unmarshal(raw, &content)
}

// unreadThreads returns the latest alerting reply time of each unread thread
// among roots, or of every unread thread in the room when roots is empty.
func (s *Dispatcher) unreadThreads(ctx context.Context, roomID id.RoomID, roots []any) (map[id.EventID]int64, error) {
	cli := s.rt.Client()
	seen, err := s.loadThreadSeen(ctx, roomID)
	if err != nil {
		return nil, err
	}
	since := max(time.Now().Add(-threadUnreadWindow).UnixMilli(), seen.All)
	query := `SELECT relates_to, MAX(timestamp) FROM event reply
		WHERE room_id=? AND relation_type='m.thread' AND sender<>? AND unread_type & 2 <> 0
		AND redacted_by IS NULL AND timestamp>?
		AND COALESCE(json_extract(COALESCE(decrypted,content),'$."` + broadcastOutsideThreadKey + `"'),0)<>1
		AND timestamp>COALESCE((SELECT MAX(receipt.timestamp) FROM receipt
			WHERE receipt.room_id=reply.room_id AND receipt.user_id=? AND receipt.thread_id=reply.relates_to
			AND receipt.receipt_type IN ('m.read','m.read.private')),0)`
	args := []any{roomID, cli.Account.UserID, since, cli.Account.UserID}
	if len(roots) > 0 {
		query += ` AND relates_to IN (` + sqlSlots(len(roots)) + `)`
		args = append(args, roots...)
	}
	rows, err := cli.DB.Query(ctx, query+` GROUP BY relates_to`, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	unread := make(map[id.EventID]int64)
	for rows.Next() {
		var root id.EventID
		var latest int64
		if err = rows.Scan(&root, &latest); err != nil {
			return nil, err
		}
		if latest > seen.Roots[root] {
			unread[root] = latest
		}
	}
	return unread, rows.Err()
}

// listUnreadThreads returns the roots of the chat's unread threads, the most
// recently active first.
func (s *Dispatcher) listUnreadThreads(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID string `json:"chatID"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID, err := required(req.ChatID, "chatID")
	if err != nil {
		return nil, err
	}
	roomID := id.RoomID(chatID)
	unread, err := s.unreadThreads(ctx, roomID, nil)
	if err != nil {
		return nil, err
	}
	roots := slices.SortedFunc(maps.Keys(unread), func(a, b id.EventID) int { return cmp.Compare(unread[b], unread[a]) })
	if len(roots) > unreadThreadLimit {
		roots = roots[:unreadThreadLimit]
	}
	ids := make([]string, len(roots))
	for index, root := range roots {
		ids[index] = string(root)
	}
	// A root this device never received has nothing to list.
	events, err := s.loadRoomEventsByID(ctx, roomID, ids)
	if err != nil {
		return nil, err
	}
	messages, err := s.mapEvents(ctx, roomID, events)
	if err != nil {
		return nil, err
	}
	slices.SortFunc(messages, func(a, b wire.Message) int {
		return cmp.Compare(unread[id.EventID(b.ID)], unread[id.EventID(a.ID)])
	})
	return wire.GetMessagesOutput{Items: messages}, nil
}

// markThreadSeen marks a thread as read, clearing its unread dot on
// every device. It writes only when the thread was unread.
func (s *Dispatcher) markThreadSeen(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID       string `json:"chatID"`
		ThreadRootID string `json:"threadRootID"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	roomID, rootID, err := threadTarget(req.ChatID, req.ThreadRootID)
	if err != nil {
		return nil, err
	}
	unread, err := s.unreadThreads(ctx, roomID, []any{rootID})
	if err != nil || unread[rootID] == 0 {
		return wire.Success, err
	}
	if err = s.saveThreadSeen(ctx, roomID, func(seen *threadSeenContent, now int64) { seen.Roots[rootID] = now }); err != nil {
		return nil, err
	}
	return wire.Success, nil
}

// markAllThreadsSeen marks every thread in the room as read, as marking the
// chat as read does.
func (s *Dispatcher) markAllThreadsSeen(ctx context.Context, roomID id.RoomID) error {
	return s.saveThreadSeen(ctx, roomID, func(seen *threadSeenContent, now int64) { seen.All = now })
}

// saveThreadSeen applies mark to when threads were last read, dropping any
// thread read before the whole chat or longer ago than a reply can count.
func (s *Dispatcher) saveThreadSeen(ctx context.Context, roomID id.RoomID, mark func(seen *threadSeenContent, now int64)) error {
	seen, err := s.loadThreadSeen(ctx, roomID)
	if err != nil {
		return err
	}
	now := time.Now()
	if seen.Roots == nil {
		seen.Roots = make(map[id.EventID]int64, 1)
	}
	mark(&seen, now.UnixMilli())
	cutoff := max(now.Add(-threadSeenRetention).UnixMilli(), seen.All+1)
	maps.DeleteFunc(seen.Roots, func(_ id.EventID, at int64) bool { return at < cutoff })
	content, err := json.Marshal(seen)
	if err != nil {
		return err
	}
	cli := s.rt.Client()
	if err = cli.Client.SetRoomAccountData(ctx, roomID, threadSeenType.Type, json.RawMessage(content)); err != nil {
		return err
	}
	// Sync echoes the write later; store it now so the next read sees it.
	_, err = cli.DB.AccountData.PutRoom(ctx, cli.Account.UserID, roomID, threadSeenType, content)
	return err
}
