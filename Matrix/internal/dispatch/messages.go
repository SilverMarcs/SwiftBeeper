package dispatch

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

// messageTarget validates the chatID and messageID every message action takes.
func messageTarget(chatID, messageID string) (id.RoomID, id.EventID, error) {
	chatID, err := required(chatID, "chatID")
	if err != nil {
		return "", "", err
	}
	messageID, err = required(messageID, "messageID")
	if err != nil {
		return "", "", err
	}
	return id.RoomID(chatID), id.EventID(messageID), nil
}

func (s *Dispatcher) sendMessage(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID string `json:"chatID"`
		wire.SendMessageInput
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID, err := required(req.ChatID, "chatID")
	if err != nil {
		return nil, err
	}
	text := strings.TrimSpace(req.Text)
	hasAttachment := strings.TrimSpace(req.Attachment.UploadID) != ""
	if text == "" && !hasAttachment {
		return nil, errors.New("text or attachment is required")
	}

	cli := s.rt.Client()
	roomID := id.RoomID(chatID)
	room, err := cli.DB.Room.Get(ctx, roomID)
	if err != nil {
		return nil, fmt.Errorf("failed to get room: %w", err)
	} else if room == nil {
		return nil, errors.New("Chat not found")
	}

	var base *event.MessageEventContent
	if hasAttachment {
		if base, err = s.uploadAttachment(ctx, req.Attachment, room.EncryptionEvent != nil); err != nil {
			return nil, err
		}
	}
	var relatesTo *event.RelatesTo
	if replyTo := strings.TrimSpace(req.ReplyToMessageID); replyTo != "" {
		relatesTo = &event.RelatesTo{InReplyTo: &event.InReplyTo{EventID: id.EventID(replyTo)}}
	}

	dbEvent, err := cli.SendMessage(ctx, roomID, base, nil, text, relatesTo, nil, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to send message: %w", err)
	}
	pendingMessageID := dbEvent.TransactionID
	if pendingMessageID == "" {
		pendingMessageID = string(dbEvent.ID)
	}
	return wire.SendMessageOutput{ChatID: chatID, PendingMessageID: pendingMessageID}, nil
}

// NotificationReply sends a reply from a notification and waits for the
// server to accept it, because Apple suspends the app again right after. The
// composer's sends stay optimistic instead.
func (s *Dispatcher) NotificationReply(ctx context.Context, roomID id.RoomID, eventID id.EventID, text string) (any, error) {
	if err := s.requireLoggedInSession(); err != nil {
		return nil, err
	}
	text = strings.TrimSpace(text)
	if roomID == "" || text == "" {
		return nil, errors.New("a conversation and reply text are required")
	}
	content := &event.MessageEventContent{MsgType: event.MsgText, Body: text}
	if eventID != "" {
		content.RelatesTo = &event.RelatesTo{InReplyTo: &event.InReplyTo{EventID: eventID}}
	}
	cli := s.rt.Client()
	if !cli.State().IsVerified {
		return nil, errors.New("open Relay to finish signing in before replying")
	}
	sent, err := cli.Send(mautrix.WithMaxRetries(ctx, 0), roomID, event.EventMessage, content, false, true)
	if err != nil {
		return nil, err
	}
	if sent.ID == "" || strings.HasPrefix(string(sent.ID), "~") {
		return nil, fmt.Errorf("notification reply was not sent: %s", sent.SendError)
	}
	sent.SendError = ""
	cli.EventHandler(&jsoncmd.SendComplete{Event: sent})
	return wire.Success, nil
}

func (s *Dispatcher) editMessage(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID    string `json:"chatID"`
		MessageID string `json:"messageID"`
		Text      string `json:"text"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	roomID, eventID, err := messageTarget(req.ChatID, req.MessageID)
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(req.Text) == "" {
		return nil, errors.New("text is required")
	}

	cli := s.rt.Client()
	target, err := cli.DB.Event.GetByID(ctx, eventID)
	if err != nil {
		return nil, fmt.Errorf("failed to get target message: %w", err)
	}
	if target == nil {
		return nil, errors.New("Message not found")
	}
	if eventHasAttachment(target) {
		return nil, errors.New("messageID: cannot edit messages with attachments")
	}
	relatesTo := &event.RelatesTo{Type: event.RelReplace, EventID: eventID}
	if _, err = cli.SendMessage(ctx, roomID, nil, nil, req.Text, relatesTo, nil, nil); err != nil {
		return nil, fmt.Errorf("failed to edit message: %w", err)
	}
	return wire.Success, nil
}

type reactionRequest struct {
	ChatID      string `json:"chatID"`
	MessageID   string `json:"messageID"`
	ReactionKey string `json:"reactionKey"`
}

// decodeReaction decodes and validates a reaction command. The key in req is
// left as given; validation only requires it to be non-blank.
func decodeReaction(input json.RawMessage) (req reactionRequest, roomID id.RoomID, eventID id.EventID, err error) {
	if err = decodeJSON(input, &req); err != nil {
		return
	}
	if roomID, eventID, err = messageTarget(req.ChatID, req.MessageID); err != nil {
		return
	}
	_, err = required(req.ReactionKey, "reactionKey")
	return
}

func (s *Dispatcher) addReaction(ctx context.Context, input json.RawMessage) (any, error) {
	req, roomID, eventID, err := decodeReaction(input)
	if err != nil {
		return nil, err
	}
	content := &event.ReactionEventContent{
		RelatesTo: event.RelatesTo{Type: event.RelAnnotation, EventID: eventID, Key: req.ReactionKey},
	}
	if _, err = s.rt.Client().Send(ctx, roomID, event.EventReaction, content, false, false); err != nil {
		return nil, fmt.Errorf("failed to add reaction: %w", err)
	}
	return wire.Success, nil
}

// removeReaction redacts the user's own reactions with this key.
func (s *Dispatcher) removeReaction(ctx context.Context, input json.RawMessage) (any, error) {
	req, roomID, eventID, err := decodeReaction(input)
	if err != nil {
		return nil, err
	}
	reactionKey := strings.TrimSpace(req.ReactionKey)
	cli := s.rt.Client()
	related, err := cli.DB.Event.GetRelatedEvents(ctx, roomID, eventID, event.RelAnnotation)
	if err != nil {
		return nil, fmt.Errorf("failed to query related events: %w", err)
	}
	var toRedact []id.EventID
	for _, evt := range related {
		if evt.Sender != cli.Account.UserID || evt.RedactedBy != "" {
			continue
		}
		var reaction event.ReactionEventContent
		if json.Unmarshal(evt.GetContent(), &reaction) == nil && reaction.RelatesTo.Key == reactionKey {
			toRedact = append(toRedact, evt.ID)
		}
	}
	for _, reactionEventID := range toRedact {
		if _, err = cli.Client.RedactEvent(ctx, roomID, reactionEventID, mautrix.ReqRedact{}); err != nil {
			return nil, fmt.Errorf("failed to remove reaction: %w", err)
		}
	}
	return wire.Success, nil
}

func (s *Dispatcher) deleteMessage(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID    string `json:"chatID"`
		MessageID string `json:"messageID"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	roomID, eventID, err := messageTarget(req.ChatID, req.MessageID)
	if err != nil {
		return nil, err
	}
	if _, err = s.rt.Client().Client.RedactEvent(ctx, roomID, eventID, mautrix.ReqRedact{}); err != nil {
		return nil, fmt.Errorf("failed to redact event: %w", err)
	}
	return wire.Success, nil
}
