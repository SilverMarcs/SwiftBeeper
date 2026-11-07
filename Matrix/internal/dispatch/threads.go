package dispatch

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"time"

	"github.com/tidwall/gjson"
	"go.mau.fi/gomuks/pkg/hicli/database"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

const (
	// threadSummaryParticipants is how many repliers a thread root shows.
	threadSummaryParticipants = 3
	// threadMessageLimit bounds one thread's local listing, newest kept.
	threadMessageLimit = 1000
	// threadHistoryPages bounds one server fetch of a thread's replies.
	threadHistoryPages    = 5
	threadHistoryPageSize = 100

	// broadcastOutsideThreadKey is the bridge's flag for a thread reply also
	// sent to the channel (Slack's "Also send to channel").
	broadcastOutsideThreadKey = "com.beeper.broadcast_outside_thread"
)

// hiddenThreadReplySQL matches thread replies that stay out of the main
// timeline: every m.thread event that was not also sent to the chat.
const hiddenThreadReplySQL = `(COALESCE(relation_type,'')='m.thread' AND COALESCE(json_extract(COALESCE(decrypted,content),'$."` + broadcastOutsideThreadKey + `"'),0)<>1)`

// eventContent is the event's plaintext content, ignoring edits.
func eventContent(evt *database.Event) json.RawMessage {
	if evt.Decrypted != nil {
		return evt.Decrypted
	}
	return evt.Content
}

// threadRootOf returns the thread an event replies in, if any.
func threadRootOf(evt *database.Event) id.EventID {
	if evt.RelationType == event.RelThread {
		return evt.RelatesTo
	}
	return ""
}

func isThreadBroadcast(evt *database.Event) bool {
	return gjson.GetBytes(eventContent(evt), gjson.Escape(broadcastOutsideThreadKey)).Bool()
}

// isHiddenThreadReply mirrors hiddenThreadReplySQL for a loaded event.
func isHiddenThreadReply(evt *database.Event) bool {
	return threadRootOf(evt) != "" && !isThreadBroadcast(evt)
}

// nonFallbackReplyTo is the message an event actually quotes. A thread reply
// carries a reply to the thread's previous message only as a fallback for
// clients without threads; showing it would quote that message for nothing.
func nonFallbackReplyTo(evt *database.Event) id.EventID {
	replyTo := evt.GetReplyTo()
	if replyTo == "" || evt.RelationType != event.RelThread {
		return replyTo
	}
	if gjson.GetBytes(eventContent(evt), `m\.relates_to.is_falling_back`).Bool() {
		return ""
	}
	return replyTo
}

// listThread reads a thread from the local database: its root and replies,
// oldest first. Replies fetched with loadThreadHistory are stored without
// timeline positions, so the app orders a thread by timestamp.
func (s *Dispatcher) listThread(ctx context.Context, input json.RawMessage) (any, error) {
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
	cli := s.rt.Client()
	replies, err := cli.DB.Event.GetRelatedEvents(ctx, roomID, rootID, event.RelThread)
	if err != nil {
		return nil, fmt.Errorf("failed to read thread: %w", err)
	}
	if len(replies) > threadMessageLimit {
		replies = replies[len(replies)-threadMessageLimit:]
	}
	events := slices.Clone(replies)
	root, err := cli.DB.Event.GetByID(ctx, rootID)
	if err != nil {
		return nil, fmt.Errorf("failed to read thread root: %w", err)
	}
	if root != nil {
		events = append(events, root)
	}
	messages, err := s.mapEvents(ctx, roomID, events)
	if err != nil {
		return nil, err
	}
	output := wire.ListThreadOutput{Items: make([]wire.Message, 0, len(messages))}
	for _, message := range messages {
		if message.ID == string(rootID) {
			output.Root = &message
		} else {
			output.Items = append(output.Items, message)
		}
	}
	return output, nil
}

// loadThreadHistory fetches the thread's root and replies from the homeserver
// into the local database, where listThread reads them. Sync only delivers
// replies sent while this device follows the room.
func (s *Dispatcher) loadThreadHistory(ctx context.Context, input json.RawMessage) (any, error) {
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
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	cli := s.rt.Client()
	if _, err = cli.GetEvent(ctx, roomID, rootID); err != nil {
		return nil, err
	}
	since := ""
	for range threadHistoryPages {
		resp, err := cli.PaginateManual(ctx, roomID, rootID, since, mautrix.DirectionBackward, threadHistoryPageSize)
		if err != nil {
			return nil, err
		}
		if resp.NextBatch == "" || resp.NextBatch == since || len(resp.Events) == 0 {
			break
		}
		since = resp.NextBatch
	}
	return wire.Success, nil
}

func threadTarget(chatID, rootID string) (id.RoomID, id.EventID, error) {
	roomID, err := required(chatID, "chatID")
	if err != nil {
		return "", "", err
	}
	root, err := required(rootID, "threadRootID")
	if err != nil {
		return "", "", err
	}
	return id.RoomID(roomID), id.EventID(root), nil
}

// mapEvents maps one room's events with their edits, names, reactions and
// thread summaries, skipping events that are not messages.
func (s *Dispatcher) mapEvents(ctx context.Context, roomID id.RoomID, events []*database.Event) ([]wire.Message, error) {
	if err := s.populateTimelinePositions(ctx, events); err != nil {
		return nil, err
	}
	if err := s.populateLastEditRefs(ctx, events); err != nil {
		return nil, err
	}
	names := s.loadNamesForEvents(ctx, events)[roomID]
	// Messages still render when their reactions can't be read.
	reactions, _ := s.loadReactionMap(ctx, roomID, events)
	messages := make([]wire.Message, 0, len(events))
	for _, evt := range events {
		if message, err := s.mapEventToMessage(evt, names, reactions); err == nil {
			message.TransactionID = evt.TransactionID
			messages = append(messages, message)
		}
	}
	s.applyThreadSummaries(ctx, roomID, events, messages)
	return messages, nil
}

// applyThreadSummaries sets Thread on every message that has replies. Local
// replies are counted directly; the server's bundled count in the root's
// unsigned data covers replies older than the local history.
func (s *Dispatcher) applyThreadSummaries(ctx context.Context, roomID id.RoomID, events []*database.Event, messages []wire.Message) {
	summaries := s.loadThreadSummaries(ctx, roomID, events)
	if len(summaries) == 0 {
		return
	}
	for index := range messages {
		if summary := summaries[id.EventID(messages[index].ID)]; summary != nil {
			messages[index].Thread = summary
		}
	}
}

func (s *Dispatcher) loadThreadSummaries(ctx context.Context, roomID id.RoomID, events []*database.Event) map[id.EventID]*wire.ThreadSummary {
	// Thread replies can't be roots themselves.
	var rootIDs []any
	for _, evt := range events {
		if threadRootOf(evt) == "" && evt.RelationType != event.RelReplace {
			rootIDs = append(rootIDs, evt.ID)
		}
	}
	if len(rootIDs) == 0 {
		return nil
	}
	type tally struct {
		count   int
		senders []id.UserID
	}
	tallies := make(map[id.EventID]*tally)
	cli := s.rt.Client()
	for chunk := range slices.Chunk(rootIDs, 200) {
		args := append([]any{roomID}, chunk...)
		rows, err := cli.DB.Query(ctx, `SELECT relates_to,sender FROM event
			WHERE room_id=? AND relation_type='m.thread' AND relates_to IN (`+sqlSlots(len(chunk))+`)
			AND redacted_by IS NULL AND event_id LIKE '$%' ORDER BY timestamp DESC`, args...)
		if err != nil {
			return nil
		}
		for rows.Next() {
			var rootID id.EventID
			var sender id.UserID
			if rows.Scan(&rootID, &sender) != nil {
				continue
			}
			entry := tallies[rootID]
			if entry == nil {
				entry = &tally{}
				tallies[rootID] = entry
			}
			entry.count++
			if len(entry.senders) < threadSummaryParticipants && !slices.Contains(entry.senders, sender) {
				entry.senders = append(entry.senders, sender)
			}
		}
		rows.Close()
	}
	// The server's bundled aggregation, as of when the root was received.
	for _, evt := range events {
		var unsigned struct {
			Relations struct {
				Thread *struct {
					Count  int `json:"count"`
					Latest *struct {
						Sender id.UserID `json:"sender"`
					} `json:"latest_event"`
				} `json:"m.thread"`
			} `json:"m.relations"`
		}
		if len(evt.Unsigned) == 0 || json.Unmarshal(evt.Unsigned, &unsigned) != nil || unsigned.Relations.Thread == nil {
			continue
		}
		bundled := unsigned.Relations.Thread
		if bundled.Count <= 0 {
			continue
		}
		entry := tallies[evt.ID]
		if entry == nil {
			entry = &tally{}
			tallies[evt.ID] = entry
		}
		entry.count = max(entry.count, bundled.Count)
		if latest := bundled.Latest; latest != nil && latest.Sender != "" &&
			len(entry.senders) < threadSummaryParticipants && !slices.Contains(entry.senders, latest.Sender) {
			entry.senders = append(entry.senders, latest.Sender)
		}
	}
	if len(tallies) == 0 {
		return nil
	}
	var senders []id.UserID
	for _, entry := range tallies {
		senders = append(senders, entry.senders...)
	}
	users := s.loadRoomUsers(ctx, roomID, senders)
	output := make(map[id.EventID]*wire.ThreadSummary, len(tallies))
	for rootID, entry := range tallies {
		summary := &wire.ThreadSummary{ReplyCount: entry.count, Participants: make([]wire.User, 0, len(entry.senders))}
		for _, sender := range entry.senders {
			if user, ok := users[sender]; ok {
				summary.Participants = append(summary.Participants, user)
			} else {
				summary.Participants = append(summary.Participants, newUser(string(sender), "", "", "", sender == cli.Account.UserID))
			}
		}
		output[rootID] = summary
	}
	return output
}

// loadRoomUsers resolves profiles from the room's member events.
func (s *Dispatcher) loadRoomUsers(ctx context.Context, roomID id.RoomID, userIDs []id.UserID) map[id.UserID]wire.User {
	output := make(map[id.UserID]wire.User, len(userIDs))
	keys := make([]database.RoomStateGUID, 0, len(userIDs))
	for _, userID := range slices.Compact(slices.Sorted(slices.Values(userIDs))) {
		keys = append(keys, database.RoomStateGUID{RoomID: roomID, Type: event.StateMember, StateKey: string(userID)})
	}
	if len(keys) == 0 {
		return output
	}
	members, err := s.rt.Client().DB.CurrentState.GetMany(ctx, keys)
	if err != nil {
		return output
	}
	self := string(s.rt.Client().Account.UserID)
	for _, member := range members {
		if member.StateKey == nil {
			continue
		}
		var content event.MemberEventContent
		if json.Unmarshal(member.GetContent(), &content) == nil {
			output[id.UserID(*member.StateKey)] = userFromMemberEvent(*member.StateKey, content, self)
		}
	}
	return output
}

// outgoingRelation builds m.relates_to for a send. A thread reply carries a
// fallback reply to the thread's latest message for clients without threads,
// unless it quotes a specific message.
func (s *Dispatcher) outgoingRelation(ctx context.Context, roomID id.RoomID, replyTo, threadRoot id.EventID) (*event.RelatesTo, error) {
	if threadRoot == "" {
		if replyTo == "" {
			return nil, nil
		}
		return &event.RelatesTo{InReplyTo: &event.InReplyTo{EventID: replyTo}}, nil
	}
	relatesTo := &event.RelatesTo{}
	if replyTo != "" {
		relatesTo.SetReplyTo(replyTo)
	}
	latest, err := s.latestThreadEventID(ctx, roomID, threadRoot)
	if err != nil {
		return nil, err
	}
	return relatesTo.SetThread(threadRoot, latest), nil
}

// latestThreadEventID is the thread's newest message, or the root when it has
// no replies yet.
func (s *Dispatcher) latestThreadEventID(ctx context.Context, roomID id.RoomID, threadRoot id.EventID) (id.EventID, error) {
	var latest string
	err := s.rt.Client().DB.QueryRow(ctx, `SELECT event_id FROM event
		WHERE room_id=? AND relation_type='m.thread' AND relates_to=? AND event_id LIKE '$%'
		ORDER BY timestamp DESC LIMIT 1`, roomID, threadRoot).Scan(&latest)
	if errors.Is(err, sql.ErrNoRows) {
		return threadRoot, nil
	} else if err != nil {
		return "", fmt.Errorf("failed to read thread: %w", err)
	}
	return id.EventID(latest), nil
}
