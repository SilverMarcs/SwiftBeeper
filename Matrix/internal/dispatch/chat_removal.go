package dispatch

import (
	"context"
	"encoding/json"
	"fmt"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

// deleteChat asks the room's bridge to delete the chat on its network, which
// then deletes the room. Rooms whose bridge can't do that are left and
// forgotten instead, which removes them here only.
func (s *Dispatcher) deleteChat(ctx context.Context, input json.RawMessage) (any, error) {
	roomID, err := decodeChatID(input)
	if err != nil {
		return nil, err
	}
	if _, err = s.chatRoom(ctx, roomID); err != nil {
		return nil, err
	}
	cli := s.rt.Client()
	if s.roomFeatures(ctx, roomID).DeleteChat {
		if _, err = cli.Send(ctx, roomID, event.BeeperDeleteChat, &event.BeeperChatDeleteEventContent{}, false, true); err != nil {
			return nil, fmt.Errorf("failed to delete chat: %w", err)
		}
		return wire.Success, nil
	}
	if err = s.leaveRoom(ctx, roomID); err != nil {
		return nil, err
	}
	// Forgetting is cleanup only; the chat is already gone from the list.
	_, _ = cli.Client.ForgetRoom(ctx, roomID)
	return wire.Success, nil
}

// leaveChat leaves the room, which the bridge relays as leaving the group.
func (s *Dispatcher) leaveChat(ctx context.Context, input json.RawMessage) (any, error) {
	roomID, err := decodeChatID(input)
	if err != nil {
		return nil, err
	}
	if err = s.leaveRoom(ctx, roomID); err != nil {
		return nil, err
	}
	return wire.Success, nil
}

func (s *Dispatcher) leaveRoom(ctx context.Context, roomID id.RoomID) error {
	if _, err := s.rt.Client().Client.LeaveRoom(ctx, roomID); err != nil {
		return fmt.Errorf("failed to leave chat: %w", err)
	}
	return nil
}

func decodeChatID(input json.RawMessage) (id.RoomID, error) {
	var req struct {
		ChatID string `json:"chatID"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return "", err
	}
	chatID, err := required(req.ChatID, "chatID")
	return id.RoomID(chatID), err
}
