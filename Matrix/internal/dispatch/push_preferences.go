package dispatch

import (
	"context"
	"sort"
)

// Export notification preferences from one local query. The gateway receives
// no Matrix credentials, message content, or encryption keys.
func (s *Dispatcher) PushPreferences(ctx context.Context) (any, error) {
	states, err := s.loadRoomAccountDataStates(ctx)
	if err != nil {
		return nil, err
	}
	rooms := make([]map[string]any, 0)
	for roomID, state := range states {
		until := state.MutedUntil
		if state.InArchive() {
			until = -1
		}
		if until != 0 {
			rooms = append(rooms, map[string]any{"roomID": string(roomID), "blockedUntil": until})
		}
	}
	sort.Slice(rooms, func(i, j int) bool { return rooms[i]["roomID"].(string) < rooms[j]["roomID"].(string) })
	return map[string]any{"rooms": rooms}, nil
}
