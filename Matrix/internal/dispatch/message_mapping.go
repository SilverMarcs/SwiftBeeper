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
		LinkedMessageID: string(evt.GetReplyTo()),
		Reactions:       reactions[evt.ID],
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
	result, err := s.rt.Client().DB.Event.GetReactions(ctx, roomID, eventIDs...)
	if err != nil {
		return nil, fmt.Errorf("failed to read reactions: %w", err)
	}
	output := make(map[id.EventID][]wire.Reaction, len(result))
	for evtID, reactionResult := range result {
		if reactionResult == nil || len(reactionResult.Events) == 0 {
			continue
		}
		seen := make(map[string]struct{})
		reactions := make([]wire.Reaction, 0, len(reactionResult.Events))
		for _, reactionEvt := range reactionResult.Events {
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
