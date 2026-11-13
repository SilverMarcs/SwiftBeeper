package dispatch

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

// The kinds of messages a chat's info screen browses.
const (
	chatMediaKindMedia = "media"
	chatMediaKindFiles = "files"
	chatMediaKindLinks = "links"
)

const chatMediaPageSize = 60

// chatMessageContentSQL is a timeline row's plaintext content, ignoring edits.
const chatMessageContentSQL = `COALESCE(event.decrypted,event.content)`

// chatMessageRowSQL limits timeline rows to messages that are still shown:
// no edits, redactions, stickers or state.
const chatMessageRowSQL = ` AND (event.type='m.room.message' OR event.decrypted_type='m.room.message')
	AND (event.relation_type IS NULL OR event.relation_type<>'m.replace') AND event.redacted_by IS NULL`

// chatMediaKindSQL is the condition selecting one kind from content, a SQL
// expression for the message's plaintext content. Voice notes are left out of
// files; they are part of the conversation rather than something to look up.
func chatMediaKindSQL(kind, content string) (string, error) {
	msgType := `json_extract(` + content + `,'$.msgtype')`
	switch kind {
	case chatMediaKindMedia:
		return msgType + ` IN ('m.image','m.video')`, nil
	case chatMediaKindFiles:
		return `(` + msgType + `='m.file' OR (` + msgType + `='m.audio' AND json_extract(` + content +
			`,'$."org.matrix.msc3245.voice"') IS NULL))`, nil
	case chatMediaKindLinks:
		body := `json_extract(` + content + `,'$.body')`
		return `(` + msgType + ` IN ('m.text','m.emote') AND (` + body + ` LIKE '%http://%' OR ` + body + ` LIKE '%https://%'))`, nil
	default:
		return "", fmt.Errorf("unknown media kind: %s", kind)
	}
}

// getChatInfo counts the chat's media, files and links. It reads only the
// local store.
func (s *Dispatcher) getChatInfo(ctx context.Context, input json.RawMessage) (any, error) {
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
	if _, err = s.chatRoom(ctx, roomID); err != nil {
		return nil, err
	}

	var conditions []string
	for _, kind := range []string{chatMediaKindMedia, chatMediaKindFiles, chatMediaKindLinks} {
		condition, _ := chatMediaKindSQL(kind, "c")
		conditions = append(conditions, `COALESCE(SUM(`+condition+`),0)`)
	}
	query := `SELECT ` + strings.Join(conditions, ",") + ` FROM (
		SELECT ` + chatMessageContentSQL + ` AS c FROM timeline JOIN event ON event.rowid=timeline.event_rowid
		WHERE timeline.room_id=?` + chatMessageRowSQL + `)`
	var output wire.ChatInfoOutput
	if err = s.rt.Client().DB.QueryRow(ctx, query, roomID).Scan(&output.MediaCount, &output.FileCount, &output.LinkCount); err != nil {
		return nil, fmt.Errorf("failed to count chat media: %w", err)
	}
	output.CanDeleteChat = s.roomFeatures(ctx, roomID).DeleteChat
	return output, nil
}

// listChatMedia pages through one kind of the chat's messages, newest first.
func (s *Dispatcher) listChatMedia(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID string `json:"chatID"`
		Kind   string `json:"kind"`
		Cursor string `json:"cursor"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID, err := required(req.ChatID, "chatID")
	if err != nil {
		return nil, err
	}
	return s.loadChatMediaPage(ctx, id.RoomID(chatID), req.Kind, req.Cursor)
}

// loadChatMediaPage reads up to a page of one kind of the chat's messages,
// older than cursor, newest first. Reels are dropped after mapping, so a page
// can hold fewer and still have more.
func (s *Dispatcher) loadChatMediaPage(ctx context.Context, roomID id.RoomID, kind, cursor string) (wire.ChatMessagePageOutput, error) {
	const limit = chatMediaPageSize
	condition, err := chatMediaKindSQL(kind, chatMessageContentSQL)
	if err != nil {
		return wire.ChatMessagePageOutput{}, err
	}
	room, err := s.chatRoom(ctx, roomID)
	if err != nil {
		return wire.ChatMessagePageOutput{}, err
	}
	hasCursor := 0
	var before int64
	if cursor != "" {
		if before, err = strconv.ParseInt(cursor, 10, 64); err != nil {
			return wire.ChatMessagePageOutput{}, fmt.Errorf("invalid cursor: %w", err)
		}
		hasCursor = 1
	}
	query := timelineSelectBase + chatMessageRowSQL + ` AND ` + condition + ` AND (?=0 OR timeline.rowid<?) ORDER BY timeline.rowid DESC LIMIT ?`
	events, err := s.queryEvents(ctx, query, roomID, hasCursor, before, limit+1)
	if err != nil {
		return wire.ChatMessagePageOutput{}, fmt.Errorf("failed to query chat messages: %w", err)
	}
	output := wire.ChatMessagePageOutput{
		Items:            make([]wire.Message, 0, len(events)),
		HasMore:          len(events) > limit,
		HasServerHistory: room.PrevBatch != database.PrevBatchPaginationComplete,
	}
	if output.HasMore {
		events = events[:limit]
	}
	if len(events) == 0 {
		return output, nil
	}
	// Set on the last page too, so a page read after fetching server history
	// continues from here.
	output.Cursor = strconv.FormatInt(int64(events[len(events)-1].TimelineRowID), 10)
	if err = s.populateLastEditRefs(ctx, events); err != nil {
		return wire.ChatMessagePageOutput{}, err
	}
	names := s.loadNamesForEvents(ctx, events)[roomID]
	for _, evt := range events {
		message, err := s.mapEventToMessage(evt, names, nil)
		// A Reel shows only its thumbnail until it's resolved, which the
		// timeline does as it plays.
		isReel := len(message.Attachments) > 0 && message.Attachments[0].Type == wire.AttachmentTypeReel
		if err != nil || (kind == chatMediaKindMedia && isReel) {
			continue
		}
		output.Items = append(output.Items, message)
	}
	return output, nil
}

func (s *Dispatcher) chatRoom(ctx context.Context, roomID id.RoomID) (*database.Room, error) {
	room, err := s.rt.Client().DB.Room.Get(ctx, roomID)
	if err != nil {
		return nil, fmt.Errorf("failed to get room: %w", err)
	} else if room == nil {
		return nil, errors.New("Chat not found")
	}
	return room, nil
}

// roomFeatures reads the features the room's bridge declares; rooms without
// a bridge declare none.
func (s *Dispatcher) roomFeatures(ctx context.Context, roomID id.RoomID) event.RoomFeatures {
	var features event.RoomFeatures
	state, err := s.rt.Client().DB.CurrentState.Get(ctx, roomID, event.StateBeeperRoomFeatures, "")
	if err == nil && state != nil {
		_ = json.Unmarshal(state.GetContent(), &features)
	}
	return features
}
