package dispatch

import (
	"context"
	"fmt"
	"strings"

	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

// MobileReply finishes the encrypted send before Apple suspends the app again.
// The normal composer remains optimistic; notification replies need an ack.
func (s *Dispatcher) MobileReply(ctx context.Context, roomID id.RoomID, eventID id.EventID, text string) (any, error) {
	if err := s.requireLoggedInSession(); err != nil {
		return nil, err
	}
	text = strings.TrimSpace(text)
	if roomID == "" || text == "" {
		return nil, fmt.Errorf("a conversation and reply text are required")
	}
	content := &event.MessageEventContent{MsgType: event.MsgText, Body: text}
	if eventID != "" {
		content.RelatesTo = &event.RelatesTo{InReplyTo: &event.InReplyTo{EventID: eventID}}
	}
	cli := s.rt.Client()
	if !cli.State().IsVerified {
		return nil, fmt.Errorf("open Relay to finish signing in before replying")
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
	return map[string]any{"success": true}, nil
}
