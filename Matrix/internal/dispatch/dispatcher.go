// Package dispatch maps the Swift app's JSON commands to Matrix operations on
// the local gomuks client, and turns sync results into realtime changes.
package dispatch

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"relay/core/internal/gomuksruntime"
)

// Dispatcher maps in-process Swift commands to Matrix operations.
type Dispatcher struct {
	rt     *gomuksruntime.Runtime
	events *eventHub
}

func New(rt *gomuksruntime.Runtime) *Dispatcher {
	s := &Dispatcher{rt: rt}
	s.events = newEventHub(s)
	rt.SetEventHandler(s.events.enqueue)
	return s
}

// Execute runs one command. Login commands work without a session; every
// other command requires one.
func (s *Dispatcher) Execute(ctx context.Context, action string, input json.RawMessage) (any, error) {
	switch action {
	case "state":
		return s.clientState()
	case "beeper-start-login":
		return s.beeperStartLogin(ctx, input)
	case "beeper-request-code":
		return s.beeperRequestCode(ctx, input)
	case "beeper-submit-code":
		return s.beeperSubmitCode(ctx, input)
	case "login-custom":
		return s.loginCustom(ctx, input)
	case "verify":
		return s.verify(ctx, input)
	}
	if err := s.requireLoggedInSession(); err != nil {
		return nil, err
	}
	switch action {
	case "session":
		return s.getSession(ctx)
	case "list-chats":
		return s.listChats(ctx, input, chatPageSize)
	case "search-chats":
		return s.listChats(ctx, input, searchChatsLimit)
	case "get-chat":
		return s.getChat(ctx, input)
	case "archive-chat":
		return s.archiveChat(ctx, input)
	case "mute-chat":
		return s.muteChat(ctx, input)
	case "mark-chat-read":
		return s.markChatRead(ctx, input)
	case "list-messages":
		return s.listMessages(ctx, input)
	case "resolve-media":
		return s.resolveMedia(ctx, input)
	case "send-message":
		return s.sendMessage(ctx, input)
	case "edit-message":
		return s.editMessage(ctx, input)
	case "add-reaction":
		return s.addReaction(ctx, input)
	case "remove-reaction":
		return s.removeReaction(ctx, input)
	case "delete-message":
		return s.deleteMessage(ctx, input)
	default:
		return nil, fmt.Errorf("unknown Matrix command: %s", action)
	}
}

func (s *Dispatcher) requireLoggedInSession() error {
	cli := s.rt.Client()
	if cli == nil || cli.Account == nil || cli.Client == nil || cli.Client.HomeserverURL == nil {
		return errors.New("A logged-in Matrix session is required")
	}
	return nil
}

// decodeJSON reads a command's arguments, which share the JSON object with
// its action name.
func decodeJSON(input json.RawMessage, out any) error {
	if err := json.Unmarshal(input, out); err != nil {
		return fmt.Errorf("invalid arguments: %w", err)
	}
	return nil
}

// required trims an argument and reports it by name when it is empty.
func required(value, name string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", errors.New(name + " is required")
	}
	return value, nil
}

// sqlSlots returns count comma-separated SQL placeholders.
func sqlSlots(count int) string { return strings.TrimSuffix(strings.Repeat("?,", count), ",") }

func randomID() string {
	buf := make([]byte, 16)
	_, _ = rand.Read(buf)
	return hex.EncodeToString(buf)
}
