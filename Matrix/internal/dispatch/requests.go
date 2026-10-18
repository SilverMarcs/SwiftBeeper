package dispatch

import (
	"encoding/json"
	"errors"

	"net/http"

	"strconv"
	"strings"

	"relay/core/internal/cursor"
	errs "relay/core/internal/errors"
)

type apiHandler func(http.ResponseWriter, *http.Request) error

func (s *Dispatcher) requireLoggedInSession() error {
	cli := s.rt.Client()
	if cli == nil || cli.Account == nil || cli.Client == nil || cli.Client.HomeserverURL == nil {
		return errs.Forbidden("A logged-in Matrix session is required")
	}
	return nil
}

func writeJSON(w http.ResponseWriter, value any) error {
	w.Header().Set("Content-Type", "application/json")
	return json.NewEncoder(w).Encode(value)
}

func decodeJSON(r *http.Request, out any) error {
	decoder := json.NewDecoder(r.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(out); err != nil {
		return errs.Validation(map[string]any{"error": err.Error()})
	}
	return nil
}

func readChatID(r *http.Request, bodyChatID string) string {
	if chatID := r.PathValue("chatID"); chatID != "" {
		return chatID
	}
	if bodyChatID != "" {
		return bodyChatID
	}
	if chatID := r.URL.Query().Get("chatID"); chatID != "" {
		return chatID
	}
	return ""
}

func parseDirection(raw string) (string, error) {
	direction := strings.TrimSpace(raw)
	if direction == "" {
		return "before", nil
	}
	if direction != "before" && direction != "after" {
		return "", errs.Validation(map[string]any{"direction": "must be one of: before, after"})
	}
	return direction, nil
}

func parseParticipantLimit(raw string) (int, error) {
	if raw == "" {
		return -1, nil
	}
	limit, err := strconv.Atoi(raw)
	if err != nil {
		return 0, errs.Validation(map[string]any{"maxParticipantCount": "must be an integer"})
	}
	if limit < -1 || limit > 500 {
		return 0, errs.Validation(map[string]any{"maxParticipantCount": "must be between -1 and 500"})
	}
	return limit, nil
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
		return 0, errs.Validation(map[string]any{"cursor": err.Error()})
	}
	if decoded.TimelineRowID == 0 {
		return 0, errs.Validation(map[string]any{"cursor": "timeline_row_id is required"})
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
		return nil, errs.Validation(map[string]any{"cursor": err.Error()})
	}
	if decoded.TS == 0 {
		return nil, errs.Validation(map[string]any{"cursor": "ts is required"})
	}
	return &decoded, nil
}

func parseAccountIDs(r *http.Request) []string {
	return parseCSVQueryValues(r.URL.Query()["accountIDs"])
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
		if err != nil && !errors.Is(err, http.ErrNotSupported) {
			return err
		}
	}
	return nil
}
