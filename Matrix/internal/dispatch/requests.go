package dispatch

import (
	"encoding/json"
	"errors"
	"fmt"
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
