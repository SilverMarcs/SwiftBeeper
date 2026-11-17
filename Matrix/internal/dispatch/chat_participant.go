package dispatch

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
)

// getChatParticipant reads one person's profile in a chat from their member
// event, including someone who has since left. A chat's participants are
// only a sample, so a mention of someone outside it looks them up here.
func (s *Dispatcher) getChatParticipant(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID string `json:"chatID"`
		UserID string `json:"userID"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID, err := required(req.ChatID, "chatID")
	if err != nil {
		return nil, err
	}
	userID, err := required(req.UserID, "userID")
	if err != nil {
		return nil, err
	}
	member, err := s.rt.Client().DB.CurrentState.Get(ctx, id.RoomID(chatID), event.StateMember, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to read member: %w", err)
	}
	if member == nil {
		return nil, errors.New("Participant not found")
	}
	var content event.MemberEventContent
	if err = json.Unmarshal(member.GetContent(), &content); err != nil {
		return nil, fmt.Errorf("failed to read member: %w", err)
	}
	return userFromMemberEvent(userID, content, string(s.rt.Client().Account.UserID)), nil
}
