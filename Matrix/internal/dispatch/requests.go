package dispatch

import (
	"encoding/json"
	"errors"
	"fmt"

	"strconv"
	"strings"

	"relay/core/internal/cursor"
)

func (s *Dispatcher) requireLoggedInSession() error {
	cli := s.rt.Client()
	if cli == nil || cli.Account == nil || cli.Client == nil || cli.Client.HomeserverURL == nil {
		return errors.New("A logged-in Matrix session is required")
	}
	return nil
}

func decodeJSON(input json.RawMessage, out any) error {
	// The command name shares the object with its typed arguments.
	if err := json.Unmarshal(input, out); err != nil {
		return fmt.Errorf("invalid arguments: %w", err)
	}
	return nil
}

func parseDirection(raw string) (string, error) {
	direction := strings.TrimSpace(raw)
	if direction == "" {
		return "before", nil
	}
	if direction != "before" && direction != "after" {
		return "", errors.New("direction: must be one of: before, after")
	}
	return direction, nil
}

func parseMessageCursor(raw string) (int64, error) {
	if raw == "" {
		return 0, nil
	}
	if rowID, err := strconv.ParseInt(raw, 10, 64); err == nil {
		return rowID, nil
	}
	var decoded cursor.MessageCursor
	if err := cursor.Decode(raw, &decoded); err != nil {
		return 0, fmt.Errorf("invalid cursor: %w", err)
	}
	if decoded.TimelineRowID == 0 {
		return 0, errors.New("cursor: timeline_row_id is required")
	}
	return decoded.TimelineRowID, nil
}

func parseChatCursor(raw string) (*cursor.ChatCursor, error) {
	if raw == "" {
		return nil, nil
	}
	if ts, err := strconv.ParseInt(raw, 10, 64); err == nil {
		return &cursor.ChatCursor{TS: ts}, nil
	}
	var decoded cursor.ChatCursor
	if err := cursor.Decode(raw, &decoded); err != nil {
		return nil, fmt.Errorf("invalid cursor: %w", err)
	}
	if decoded.TS == 0 {
		return nil, errors.New("cursor: ts is required")
	}
	return &decoded, nil
}

func equalsAny(value string, candidates []string) bool {
	for _, candidate := range candidates {
		if value == candidate {
			return true
		}
	}
	return false
}

func firstErr(errsToCheck ...error) error {
	for _, err := range errsToCheck {
		if err != nil {
			return err
		}
	}
	return nil
}
