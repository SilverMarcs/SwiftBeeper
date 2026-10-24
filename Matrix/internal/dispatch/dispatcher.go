package dispatch

import (
	"context"
	"encoding/json"
	"fmt"
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

func (s *Dispatcher) Execute(ctx context.Context, action string, input json.RawMessage) (any, error) {
	switch action {
	case "state":
		return s.getManageState()
	case "beeper-start-login":
		return s.manageBeeperStartLogin(ctx, input)
	case "beeper-request-code":
		return s.manageBeeperRequestCode(ctx, input)
	case "beeper-submit-code":
		return s.manageBeeperSubmitCode(ctx, input)
	case "login-custom":
		return s.manageLoginCustom(ctx, input)
	case "verify":
		return s.manageVerify(ctx, input)
	}
	if err := s.requireLoggedInSession(); err != nil {
		return nil, err
	}
	switch action {
	case "session":
		return s.getSession(ctx, input)
	case "list-chats":
		return s.listChats(ctx, input)
	case "search-chats":
		return s.searchChats(ctx, input)
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
