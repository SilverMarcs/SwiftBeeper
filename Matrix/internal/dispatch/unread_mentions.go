package dispatch

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

const mentionPageSize = 50

// listUnreadMentions reads personal mentions oldest first, across the whole
// local timeline, including thread replies. No history download is needed.
func (s *Dispatcher) listUnreadMentions(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID string  `json:"chatID"`
		After  *string `json:"after"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID, err := required(req.ChatID, "chatID")
	if err != nil {
		return nil, err
	}
	roomID := id.RoomID(chatID)
	cli := s.rt.Client()
	me := cli.Account.UserID
	var after int64
	if req.After != nil {
		if after, err = strconv.ParseInt(*req.After, 10, 64); err != nil {
			return nil, fmt.Errorf("invalid mention position: %w", err)
		}
	} else {
		room, err := cli.DB.Room.Get(ctx, roomID)
		if err != nil {
			return nil, err
		}
		if room == nil {
			return nil, fmt.Errorf("Chat not found")
		}
		if room.UnreadMessages == 0 && room.UnreadHighlights == 0 {
			// A room with no unread messages may have no retained receipt.
			// Start at its newest local event instead of resurfacing old mentions.
			err = cli.DB.QueryRow(ctx, `SELECT COALESCE(MAX(rowid),0) FROM timeline WHERE room_id=?`, roomID).Scan(&after)
			return wire.ListMentionsOutput{Items: []wire.Message{}, After: strconv.FormatInt(after, 10)}, err
		}
		// Thread-specific receipts don't read the main conversation. Private
		// receipts do, and must work just like public read receipts.
		err = cli.DB.QueryRow(ctx, `SELECT COALESCE(MAX(t.rowid),0) FROM receipt r
			JOIN event e ON e.room_id=r.room_id AND e.event_id=r.event_id
			JOIN timeline t ON t.room_id=r.room_id AND t.event_rowid=e.rowid
			WHERE r.room_id=? AND r.user_id=? AND r.receipt_type IN ('m.read','m.read.private')
			AND r.thread_id IN ('','main')`, roomID, me).Scan(&after)
		if err != nil {
			return nil, err
		}
		after, err = s.unreadPosition(ctx, room, after)
		if err != nil {
			return nil, err
		}
	}
	output := wire.ListMentionsOutput{Items: []wire.Message{}, After: strconv.FormatInt(after, 10)}
	// Use the latest edit's new content when present. The original event's
	// mention metadata is stale after an edit adds or removes a mention.
	const mentionContent = `COALESCE((SELECT json_extract(COALESCE(edit.decrypted,edit.content),'$."m.new_content"')
		FROM event edit WHERE edit.rowid=event.last_edit_rowid AND edit.redacted_by IS NULL
		AND edit.room_id=event.room_id AND edit.sender=event.sender),event.decrypted,event.content)`
	query := timelineSelectBase + ` AND timeline.rowid>? AND event.sender<>? AND event.redacted_by IS NULL
		AND (event.type IN ('m.room.message','m.sticker') OR event.decrypted_type IN ('m.room.message','m.sticker'))
		AND COALESCE(event.relation_type,'')<>'m.replace'
		AND EXISTS (SELECT 1 FROM json_each(` + mentionContent + `,'$."m.mentions".user_ids') WHERE value=?)
		ORDER BY timeline.rowid ASC LIMIT ?`
	var matches []*database.Event
	for len(matches) <= mentionPageSize {
		candidates, err := s.queryEvents(ctx, query, roomID, after, me, me, mentionPageSize+1)
		if err != nil {
			return nil, err
		}
		if err = s.populateLastEditRefs(ctx, candidates); err != nil {
			return nil, err
		}
		for _, candidate := range candidates {
			after = int64(candidate.TimelineRowID)
			var content event.MessageEventContent
			if json.Unmarshal(candidate.GetContent(), &content) != nil {
				continue
			}
			content.RemoveReplyFallback()
			content.RemovePerMessageProfileFallback()
			if explicitlyMentions(&content, me) {
				matches = append(matches, candidate)
			}
			if len(matches) > mentionPageSize {
				break
			}
		}
		if len(candidates) < mentionPageSize+1 {
			break
		}
	}
	output.HasMore = len(matches) > mentionPageSize
	if output.HasMore {
		matches = matches[:mentionPageSize]
	}
	output.Items, err = s.mapEvents(ctx, roomID, matches)
	return output, err
}
