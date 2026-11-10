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

var errSkipEvent = errors.New("skip event")

// mapEventToMessage maps a message or sticker event; anything else, edits
// included, returns errSkipEvent.
func (s *Dispatcher) mapEventToMessage(evt *database.Event, names map[string]string, reactions map[id.EventID][]wire.Reaction) (wire.Message, error) {
	evtType := evt.GetType().Type
	if evt.RelationType == event.RelReplace ||
		(evtType != event.EventMessage.Type && evtType != event.EventSticker.Type) {
		return wire.Message{}, errSkipEvent
	}
	message := wire.Message{
		ID:              string(evt.ID),
		ChatID:          string(evt.RoomID),
		SenderID:        string(evt.Sender),
		SenderName:      string(evt.Sender),
		Timestamp:       evt.Timestamp.Time.UTC(),
		SortKey:         messageSortKey(evt),
		IsSender:        evt.Sender == s.rt.Client().Account.UserID,
		IsDeleted:       evt.RedactedBy != "",
		LinkedMessageID: string(nonFallbackReplyTo(evt)),
		Reactions:       reactions[evt.ID],
	}
	if root := threadRootOf(evt); root != "" {
		message.ThreadRootID = string(root)
		message.IsThreadBroadcast = isThreadBroadcast(evt)
	}
	if name, ok := names[string(evt.Sender)]; ok {
		message.SenderName = name
	}
	if err := applyStoredMessageContent(&message, evt, evtType); err != nil {
		return wire.Message{}, errSkipEvent
	}
	return message, nil
}

func applyStoredMessageContent(message *wire.Message, evt *database.Event, evtType string) error {
	var content event.MessageEventContent
	if err := json.Unmarshal(evt.GetContent(), &content); err != nil {
		return err
	}
	// Matrix replies and bridged per-message profiles may include compatibility
	// fallback text in Body. Relay renders those structures separately, so
	// forwarding the fallback duplicates quoted text and any URLs it contains.
	content.RemoveReplyFallback()
	content.RemovePerMessageProfileFallback()
	message.Mentions = messageMentions(content.Mentions)

	if attachment, ok := messageAttachment(content, evtType); ok {
		// One media part is currently mapped per event. Its identity survives
		// a bridge edit replacing a Reel thumbnail with the actual video.
		attachment.ID = string(evt.ID)
		if unresolvedReelContent(evt.GetContent()) != nil {
			attachment.Type = wire.AttachmentTypeReel
		}
		message.Attachments = []wire.Attachment{attachment}
		// Matrix requires a Body for media and commonly fills it with the
		// filename. GetCaption returns only actual authored caption text.
		message.Text = content.GetCaption()
	} else {
		message.Text = content.Body
		if message.Text == "" && evt.LocalContent != nil {
			message.Text = evt.LocalContent.SanitizedHTML
		}
	}
	if message.Text != "" {
		message.FormattedText = messageMentionText(content)
	}
	return nil
}

// messageAttachment maps media content; ok is false for non-media messages.
func messageAttachment(content event.MessageEventContent, evtType string) (wire.Attachment, bool) {
	msgType := content.MsgType
	if evtType == event.EventSticker.Type {
		msgType = "m.sticker"
	}
	switch msgType {
	case event.MsgImage, event.MsgVideo, event.MsgAudio, event.MsgFile, "m.sticker":
	default:
		return wire.Attachment{}, false
	}
	uri := string(content.URL)
	if uri == "" && content.File != nil {
		uri = string(content.File.URL)
	}
	att := wire.Attachment{
		ID:       uri,
		SrcURL:   uri,
		FileName: content.GetFileName(),
		Type:     wire.AttachmentTypeUnknown,
	}
	if content.Info != nil {
		att.MimeType = content.Info.MimeType
		att.FileSize = float64(content.Info.Size)
		if content.Info.Width > 0 || content.Info.Height > 0 {
			att.Size = wire.AttachmentSize{Width: float64(content.Info.Width), Height: float64(content.Info.Height)}
		}
		if content.Info.Duration > 0 {
			att.Duration = float64(content.Info.Duration) / 1000.0
		}
		if content.Info.ThumbnailURL != "" {
			att.PosterImg = string(content.Info.ThumbnailURL)
		}
	}
	switch msgType {
	case event.MsgImage:
		att.Type = wire.AttachmentTypeImage
		att.IsGif = strings.EqualFold(att.MimeType, "image/gif")
	case event.MsgVideo:
		att.Type = wire.AttachmentTypeVideo
	case event.MsgAudio:
		att.Type = wire.AttachmentTypeAudio
	case "m.sticker":
		att.Type = wire.AttachmentTypeImage
	}
	return att, true
}

// messageSortKey is the event's timeline position, falling back to its row
// and then its timestamp for events not on the timeline.
func messageSortKey(evt *database.Event) string {
	if evt.TimelineRowID != 0 {
		return strconv.FormatInt(int64(evt.TimelineRowID), 10)
	}
	if evt.RowID != 0 {
		return strconv.FormatInt(int64(evt.RowID), 10)
	}
	return strconv.FormatInt(evt.Timestamp.UnixMilli(), 10)
}

func eventHasAttachment(evt *database.Event) bool {
	var content event.MessageEventContent
	if err := json.Unmarshal(evt.GetContent(), &content); err != nil {
		return false
	}
	if content.URL != "" {
		return true
	}
	return content.File != nil && content.File.URL != ""
}

// loadReactionMap returns each event's unredacted reactions, one per sender
// and key.
func (s *Dispatcher) loadReactionMap(ctx context.Context, roomID id.RoomID, events []*database.Event) (map[id.EventID][]wire.Reaction, error) {
	if len(events) == 0 {
		return map[id.EventID][]wire.Reaction{}, nil
	}
	eventIDs := make([]id.EventID, 0, len(events))
	for _, evt := range events {
		eventIDs = append(eventIDs, evt.ID)
	}
	result, err := s.loadReactionEvents(ctx, roomID, eventIDs)
	if err != nil {
		return nil, fmt.Errorf("failed to read reactions: %w", err)
	}
	output := make(map[id.EventID][]wire.Reaction, len(result))
	for evtID, reactionEvents := range result {
		seen := make(map[string]struct{})
		reactions := make([]wire.Reaction, 0, len(reactionEvents))
		for _, reactionEvt := range reactionEvents {
			if reactionEvt.RedactedBy != "" {
				continue
			}
			var reaction event.ReactionEventContent
			if json.Unmarshal(reactionEvt.GetContent(), &reaction) != nil {
				continue
			}
			key := strings.TrimSpace(reaction.RelatesTo.Key)
			if key == "" {
				continue
			}
			dedupeKey := string(reactionEvt.Sender) + "\x1f" + key
			if _, ok := seen[dedupeKey]; ok {
				continue
			}
			seen[dedupeKey] = struct{}{}
			reactions = append(reactions, wire.Reaction{
				ID:            string(reactionEvt.Sender) + key,
				ReactionKey:   key,
				ParticipantID: string(reactionEvt.Sender),
			})
		}
		if len(reactions) > 0 {
			output[evtID] = reactions
		}
	}
	return output, nil
}

// reactionEventsQuery is the SDK's reaction lookup, with the SDK's event
// columns so rows scan into database.Event.
const reactionEventsQuery = `
	SELECT rowid, -1,
	       room_id, event_id, sender, type, state_key, timestamp, content, decrypted, decrypted_type,
	       unsigned, local_content, transaction_id, redacted_by, relates_to, relation_type,
	       megolm_session_id, decryption_error, send_error, reactions, last_edit_rowid, unread_type
	FROM event
	WHERE room_id = ? AND type = 'm.reaction' AND relation_type = 'm.annotation'
	  AND redacted_by IS NULL AND relates_to IN (%s)`

// loadReactionEvents reads the reactions to the given events, grouped by the
// event they react to. The SDK's GetReactions also writes the counts back to
// each event in a write transaction, which this read doesn't need: the
// database takes its write lock at BEGIN, so every page of messages would
// queue behind sync.
func (s *Dispatcher) loadReactionEvents(ctx context.Context, roomID id.RoomID, eventIDs []id.EventID) (map[id.EventID][]*database.Event, error) {
	params := make([]any, 0, len(eventIDs)+1)
	params = append(params, roomID)
	for _, evtID := range eventIDs {
		params = append(params, evtID)
	}
	events, err := s.rt.Client().DB.Event.QueryMany(ctx, fmt.Sprintf(reactionEventsQuery, sqlSlots(len(eventIDs))), params...)
	if err != nil {
		return nil, err
	}
	output := make(map[id.EventID][]*database.Event)
	for _, evt := range events {
		output[evt.RelatesTo] = append(output[evt.RelatesTo], evt)
	}
	return output, nil
}
