package dispatch

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"io"
	"maunium.net/go/mautrix"
	matrixattachment "maunium.net/go/mautrix/crypto/attachment"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/compat"
)

const (
	messagePageSize = 40
)

const timelineSelectBase = `
	SELECT event.rowid, timeline.rowid,
	       event.room_id, event_id, sender, type, state_key, timestamp, content, decrypted, decrypted_type,
	       unsigned, local_content, transaction_id, redacted_by, relates_to, relation_type,
	       megolm_session_id, decryption_error, send_error, reactions, last_edit_rowid, unread_type
	FROM timeline
	JOIN event ON event.rowid = timeline.event_rowid
	WHERE timeline.room_id = ?
`

var errSkipEvent = errors.New("skip event")

// listMessages reads one page of the local timeline, newest first. Matrix sync
// owns ingestion; paging never touches the network.
func (s *Dispatcher) listMessages(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID string `json:"chatID"`
		// Timeline position of the oldest message already shown.
		Cursor string `json:"cursor"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	roomID := id.RoomID(strings.TrimSpace(req.ChatID))
	if roomID == "" {
		return nil, errors.New("chatID is required")
	}
	var before int64
	if req.Cursor != "" {
		var err error
		if before, err = strconv.ParseInt(req.Cursor, 10, 64); err != nil {
			return nil, fmt.Errorf("invalid cursor: %w", err)
		}
	}

	if room, err := s.rt.Client().DB.Room.Get(ctx, roomID); err != nil {
		return nil, fmt.Errorf("failed to get room: %w", err)
	} else if room == nil {
		return nil, errors.New("Chat not found")
	}

	reads, _ := s.loadLastReadSortKeys(ctx, roomID)
	lastRead, _ := strconv.ParseInt(reads[roomID], 10, 64)
	events, hasMore, err := s.loadTimelineEvents(ctx, roomID, before)
	if err != nil {
		return nil, err
	}
	if err = s.populateLastEditRefs(ctx, events); err != nil {
		return nil, err
	}
	names := s.loadNamesForEvents(ctx, events)[roomID]
	reactions, err := s.loadReactionMap(ctx, roomID, events)
	if err != nil {
		return nil, err
	}
	messages := make([]compat.Message, 0, messagePageSize)
	oldest := before
	for index, evt := range events {
		oldest = int64(evt.TimelineRowID)
		mapped, mapErr := s.mapEventToMessage(evt, names, reactions)
		if mapErr != nil {
			continue
		}
		if lastRead != 0 && !mapped.IsSender {
			sortKey, _ := strconv.ParseInt(mapped.SortKey, 10, 64)
			mapped.IsUnread = sortKey > lastRead
		}
		messages = append(messages, mapped)
		if len(messages) == messagePageSize {
			hasMore = hasMore || index < len(events)-1
			break
		}
	}

	output := compat.ListMessagesOutput{
		Items:        messages,
		HasMore:      hasMore,
		OldestCursor: strconv.FormatInt(oldest, 10),
	}
	// The app reads the other side's position only with the newest page.
	if before == 0 {
		output.LastReadByOtherSortKey = s.loadLastReadByOther(ctx, roomID)
	}
	return output, nil
}

func (s *Dispatcher) sendMessage(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID string `json:"chatID"`
		compat.SendMessageInput
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID := strings.TrimSpace(req.ChatID)
	if chatID == "" {
		return nil, errors.New("chatID is required")
	}
	text := strings.TrimSpace(req.Text)
	hasAttachment := strings.TrimSpace(req.Attachment.UploadID) != ""
	if text == "" && !hasAttachment {
		return nil, errors.New("text or attachment is required")
	}

	cli := s.rt.Client()
	roomID := id.RoomID(chatID)
	if room, err := cli.DB.Room.Get(ctx, roomID); err != nil {
		return nil, fmt.Errorf("failed to get room: %w", err)
	} else if room == nil {
		return nil, errors.New("Chat not found")
	}

	var base *event.MessageEventContent
	var err error
	if hasAttachment {
		base, err = s.buildAttachmentMessageContent(ctx, &req.Attachment, roomID)
		if err != nil {
			return nil, err
		}
	}

	var relatesTo *event.RelatesTo
	replyToMessageID := strings.TrimSpace(req.ReplyToMessageID)
	if replyToMessageID != "" {
		relatesTo = &event.RelatesTo{InReplyTo: &event.InReplyTo{EventID: id.EventID(replyToMessageID)}}
	}

	dbEvent, err := cli.SendMessage(ctx, roomID, base, nil, text, relatesTo, nil, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to send message: %w", err)
	}
	pendingMessageID := dbEvent.TransactionID
	if pendingMessageID == "" {
		pendingMessageID = string(dbEvent.ID)
	}

	return compat.SendMessageOutput{ChatID: chatID, PendingMessageID: pendingMessageID}, nil
}

func (s *Dispatcher) editMessage(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID    string `json:"chatID"`
		MessageID string `json:"messageID"`
		compat.EditMessageInput
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID := strings.TrimSpace(req.ChatID)
	if chatID == "" {
		return nil, errors.New("chatID is required")
	}
	messageID := strings.TrimSpace(req.MessageID)
	if messageID == "" {
		return nil, errors.New("messageID is required")
	}
	if strings.TrimSpace(req.Text) == "" {
		return nil, errors.New("text is required")
	}

	cli := s.rt.Client()
	targetEvent, err := cli.DB.Event.GetByID(ctx, id.EventID(messageID))
	if err != nil {
		return nil, fmt.Errorf("failed to get target message: %w", err)
	}
	if targetEvent == nil {
		return nil, errors.New("Message not found")
	}
	if eventHasAttachment(targetEvent) {
		return nil, errors.New("messageID: cannot edit messages with attachments")
	}

	relatesTo := &event.RelatesTo{Type: event.RelReplace, EventID: id.EventID(messageID)}
	if _, err = cli.SendMessage(ctx, id.RoomID(chatID), nil, nil, req.Text, relatesTo, nil, nil); err != nil {
		return nil, fmt.Errorf("failed to edit message: %w", err)
	}

	return compat.ActionSuccessOutput{Success: true}, nil
}

func (s *Dispatcher) addReaction(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID    string `json:"chatID"`
		MessageID string `json:"messageID"`
		compat.ReactionInput
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID := strings.TrimSpace(req.ChatID)
	if chatID == "" {
		return nil, errors.New("chatID is required")
	}
	messageID := strings.TrimSpace(req.MessageID)
	if messageID == "" {
		return nil, errors.New("messageID is required")
	}
	if strings.TrimSpace(req.ReactionKey) == "" {
		return nil, errors.New("reactionKey is required")
	}

	content := &event.ReactionEventContent{
		RelatesTo: event.RelatesTo{
			Type:    event.RelAnnotation,
			EventID: id.EventID(messageID),
			Key:     req.ReactionKey,
		},
	}
	if _, err := s.rt.Client().Send(ctx, id.RoomID(chatID), event.EventReaction, content, false, false); err != nil {
		return nil, fmt.Errorf("failed to add reaction: %w", err)
	}
	return compat.ActionSuccessOutput{Success: true}, nil
}

func (s *Dispatcher) removeReaction(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID    string `json:"chatID"`
		MessageID string `json:"messageID"`
		compat.ReactionInput
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID := strings.TrimSpace(req.ChatID)
	if chatID == "" {
		return nil, errors.New("chatID is required")
	}
	messageID := strings.TrimSpace(req.MessageID)
	if messageID == "" {
		return nil, errors.New("messageID is required")
	}
	reactionKey := strings.TrimSpace(req.ReactionKey)
	if reactionKey == "" {
		return nil, errors.New("reactionKey is required")
	}

	cli := s.rt.Client()
	roomID := id.RoomID(chatID)
	related, err := cli.DB.Event.GetRelatedEvents(ctx, roomID, id.EventID(messageID), event.RelAnnotation)
	if err != nil {
		return nil, fmt.Errorf("failed to query related events: %w", err)
	}
	toRedact := make([]id.EventID, 0)
	for _, evt := range related {
		if evt.Sender != cli.Account.UserID || evt.RedactedBy != "" {
			continue
		}
		var reaction event.ReactionEventContent
		if err = json.Unmarshal(evt.GetContent(), &reaction); err != nil {
			continue
		}
		if reaction.RelatesTo.Key == reactionKey {
			toRedact = append(toRedact, evt.ID)
		}
	}

	for _, reactionEventID := range toRedact {
		if _, err = cli.Client.RedactEvent(ctx, roomID, reactionEventID, mautrix.ReqRedact{}); err != nil {
			return nil, fmt.Errorf("failed to remove reaction: %w", err)
		}
	}

	return compat.ActionSuccessOutput{Success: true}, nil
}

// loadTimelineEvents reads up to one page plus one event older than before
// (or the newest when before is 0), newest first.
func (s *Dispatcher) loadTimelineEvents(ctx context.Context, roomID id.RoomID, before int64) ([]*database.Event, bool, error) {
	const limit = messagePageSize + 1
	// SQLite skips state/reaction/edit rows before materializing the local page.
	query := timelineSelectBase + ` AND (event.type IN ('m.room.message','m.sticker') OR event.decrypted_type IN ('m.room.message','m.sticker')) AND (relation_type IS NULL OR relation_type<>'m.replace')` +
		` AND (?=0 OR timeline.rowid<?) ORDER BY timeline.rowid DESC LIMIT ?`

	rows, err := s.rt.Client().DB.Query(ctx, query, roomID, before, before, limit)
	if err != nil {
		return nil, false, fmt.Errorf("failed to query timeline: %w", err)
	}
	defer rows.Close()

	events := make([]*database.Event, 0, limit)
	for rows.Next() {
		evt := &database.Event{}
		if _, scanErr := evt.Scan(rows); scanErr != nil {
			return nil, false, fmt.Errorf("failed to scan timeline event: %w", scanErr)
		}
		events = append(events, evt)
	}
	if err = rows.Err(); err != nil {
		return nil, false, fmt.Errorf("timeline query failed: %w", err)
	}

	return events, len(events) == limit, nil
}

func (s *Dispatcher) populateLastEditRefs(ctx context.Context, events []*database.Event) error {
	cli := s.rt.Client()
	if cli == nil || len(events) == 0 {
		return nil
	}

	byEditRowID := make(map[database.EventRowID][]*database.Event)
	editRowIDs := make([]database.EventRowID, 0)
	for _, evt := range events {
		if evt == nil || evt.LastEditRowID == nil {
			continue
		}
		editRowID := *evt.LastEditRowID
		if editRowID <= 0 || editRowID == evt.RowID {
			continue
		}
		if _, ok := byEditRowID[editRowID]; !ok {
			editRowIDs = append(editRowIDs, editRowID)
		}
		byEditRowID[editRowID] = append(byEditRowID[editRowID], evt)
	}
	if len(editRowIDs) == 0 {
		return nil
	}

	editEvents, err := cli.DB.Event.GetByRowIDs(ctx, editRowIDs...)
	if err != nil {
		return fmt.Errorf("failed to load edited message references: %w", err)
	}
	editByRowID := make(map[database.EventRowID]*database.Event, len(editEvents))
	for _, evt := range editEvents {
		if evt != nil {
			editByRowID[evt.RowID] = evt
		}
	}
	for editRowID, targets := range byEditRowID {
		editEvt := editByRowID[editRowID]
		if editEvt == nil || editEvt.RedactedBy != "" {
			continue
		}
		for _, target := range targets {
			target.LastEditRef = editEvt
		}
	}
	return nil
}

type reactionBundle struct {
	Names     map[string]string
	Reactions map[id.EventID][]compat.Reaction
}

func (s *Dispatcher) loadReactionMap(ctx context.Context, roomID id.RoomID, events []*database.Event) (map[id.EventID][]compat.Reaction, error) {
	if len(events) == 0 {
		return map[id.EventID][]compat.Reaction{}, nil
	}
	eventIDs := make([]id.EventID, 0, len(events))
	for _, evt := range events {
		eventIDs = append(eventIDs, evt.ID)
	}
	result, err := s.rt.Client().DB.Event.GetReactions(ctx, roomID, eventIDs...)
	if err != nil {
		return nil, fmt.Errorf("failed to read reactions: %w", err)
	}
	output := make(map[id.EventID][]compat.Reaction, len(result))
	for evtID, reactionResult := range result {
		if reactionResult == nil || len(reactionResult.Events) == 0 {
			continue
		}
		seen := make(map[string]struct{})
		reactions := make([]compat.Reaction, 0, len(reactionResult.Events))
		for _, reactionEvt := range reactionResult.Events {
			if reactionEvt.RedactedBy != "" {
				continue
			}
			var reaction event.ReactionEventContent
			if err = json.Unmarshal(reactionEvt.GetContent(), &reaction); err != nil {
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
			reactionID := string(reactionEvt.Sender) + key
			reactions = append(reactions, compat.Reaction{
				ID:            reactionID,
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

// mapEventToMessage maps a message or sticker event; anything else is skipped.
func (s *Dispatcher) mapEventToMessage(evt *database.Event, names map[string]string, reactions map[id.EventID][]compat.Reaction) (compat.Message, error) {
	evtType := evt.GetType().Type
	if evt.RelationType == event.RelReplace ||
		(evtType != event.EventMessage.Type && evtType != event.EventSticker.Type) {
		return compat.Message{}, errSkipEvent
	}
	message := compat.Message{
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
		return compat.Message{}, errSkipEvent
	}
	return message, nil
}

func applyStoredMessageContent(message *compat.Message, evt *database.Event, evtType string) error {
	var content event.MessageEventContent
	if err := json.Unmarshal(evt.GetContent(), &content); err != nil {
		return err
	}
	// Matrix replies and bridged per-message profiles may include compatibility
	// fallback text in Body. Relay renders those structures separately, so
	// forwarding the fallback duplicates quoted text and any URLs it contains.
	content.RemoveReplyFallback()
	content.RemovePerMessageProfileFallback()

	if attachment, ok := messageAttachment(content, evtType); ok {
		// One media part is currently mapped per event. Its identity survives
		// a bridge edit replacing a Reel thumbnail with the actual video.
		attachment.ID = string(evt.ID)
		if unresolvedReelContent(evt.GetContent()) != nil {
			attachment.Type = compat.AttachmentType("reel")
		}
		message.Attachments = []compat.Attachment{attachment}
		// Matrix requires a Body for media and commonly fills it with the
		// filename. GetCaption returns only actual authored caption text.
		message.Text = content.GetCaption()
	} else {
		message.Text = content.Body
		if message.Text == "" && evt.LocalContent != nil {
			message.Text = evt.LocalContent.SanitizedHTML
		}
	}
	return nil
}

func messageAttachment(content event.MessageEventContent, evtType string) (compat.Attachment, bool) {
	msgType := content.MsgType
	if evtType == event.EventSticker.Type {
		msgType = "m.sticker"
	}
	isMedia := msgType == event.MsgImage || msgType == event.MsgVideo || msgType == event.MsgAudio || msgType == event.MsgFile || msgType == "m.sticker"
	if !isMedia {
		return compat.Attachment{}, false
	}
	uri := string(content.URL)
	if uri == "" && content.File != nil {
		uri = string(content.File.URL)
	}
	att := compat.Attachment{
		ID:       uri,
		SrcURL:   uri,
		FileName: content.GetFileName(),
		MimeType: "",
		Type:     compat.AttachmentType("unknown"),
	}
	if content.Info != nil {
		att.MimeType = content.Info.MimeType
		att.FileSize = float64(content.Info.Size)
		if content.Info.Width > 0 || content.Info.Height > 0 {
			att.Size = compat.AttachmentSize{Width: float64(content.Info.Width), Height: float64(content.Info.Height)}
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
		att.Type = compat.AttachmentType("img")
		att.IsGif = strings.EqualFold(att.MimeType, "image/gif")
	case event.MsgVideo:
		att.Type = compat.AttachmentType("video")
	case event.MsgAudio:
		att.Type = compat.AttachmentType("audio")
	case "m.sticker":
		att.Type = compat.AttachmentType("img")
	}
	return att, true
}

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

func (s *Dispatcher) buildAttachmentMessageContent(ctx context.Context, attachment *compat.MessageAttachmentInput, roomID id.RoomID) (*event.MessageEventContent, error) {
	if attachment == nil {
		return nil, nil
	}
	meta, err := s.loadUploadMetadataByID(attachment.UploadID)
	if err != nil {
		return nil, err
	}
	fileName := strings.TrimSpace(attachment.FileName)
	if fileName == "" {
		fileName = meta.FileName
	}
	mimeType := strings.TrimSpace(attachment.MimeType)
	if mimeType == "" {
		mimeType = meta.MimeType
	}
	file, err := os.Open(meta.FilePath)
	if err != nil {
		return nil, fmt.Errorf("failed to open uploaded asset: %w", err)
	}
	defer file.Close()
	stat, err := file.Stat()
	if err != nil {
		return nil, fmt.Errorf("failed to stat uploaded asset: %w", err)
	}

	room, err := s.rt.Client().DB.Room.Get(ctx, roomID)
	if err != nil || room == nil {
		return nil, fmt.Errorf("attachment room lookup failed")
	}
	var uploadReader io.Reader = file
	var encryptedReader io.ReadSeekCloser
	var encryptedFile *event.EncryptedFileInfo
	uploadMime, uploadName := mimeType, fileName
	if room.EncryptionEvent != nil {
		encryptedFile = &event.EncryptedFileInfo{EncryptedFile: *matrixattachment.NewEncryptedFile()}
		encryptedReader = encryptedFile.EncryptStream(file)
		uploadReader = encryptedReader
		uploadMime, uploadName = "application/octet-stream", "encrypted"
	}
	uploadResp, err := s.rt.Client().Client.UploadMedia(ctx, mautrix.ReqUploadMedia{
		Content: uploadReader, ContentLength: stat.Size(), ContentType: uploadMime, FileName: uploadName,
	})
	if encryptedReader != nil {
		_ = encryptedReader.Close()
	}
	if err != nil {
		return nil, fmt.Errorf("failed to upload media to Matrix: %w", err)
	}

	msgType := messageTypeFromAttachment(mimeType)
	content := &event.MessageEventContent{
		MsgType:  msgType,
		Body:     fileName,
		URL:      uploadResp.ContentURI.CUString(),
		FileName: fileName,
		Info: &event.FileInfo{
			MimeType: mimeType,
			Size:     int(stat.Size()),
		},
	}
	if encryptedFile != nil {
		encryptedFile.URL = uploadResp.ContentURI.CUString()
		content.URL = ""
		content.File = encryptedFile
	}
	if attachment.Size.Width > 0 || attachment.Size.Height > 0 {
		content.Info.Width = int(attachment.Size.Width)
		content.Info.Height = int(attachment.Size.Height)
	}
	return content, nil
}

func messageTypeFromAttachment(mimeType string) event.MessageType {
	if strings.HasPrefix(mimeType, "image/") {
		return event.MsgImage
	}
	if strings.HasPrefix(mimeType, "video/") {
		return event.MsgVideo
	}
	if strings.HasPrefix(mimeType, "audio/") {
		return event.MsgAudio
	}
	return event.MsgFile
}

func (s *Dispatcher) deleteMessage(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID    string `json:"chatID"`
		MessageID string `json:"messageID"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID := strings.TrimSpace(req.ChatID)
	if chatID == "" {
		return nil, errors.New("chatID is required")
	}
	messageID := strings.TrimSpace(req.MessageID)
	if messageID == "" {
		return nil, errors.New("messageID is required")
	}

	cli := s.rt.Client()
	roomID := id.RoomID(chatID)
	eventID := id.EventID(messageID)

	_, err := cli.Client.RedactEvent(ctx, roomID, eventID, mautrix.ReqRedact{})
	if err != nil {
		return nil, fmt.Errorf("failed to redact event: %w", err)
	}

	return map[string]any{"success": true}, nil
}
