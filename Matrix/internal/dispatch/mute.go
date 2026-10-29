package dispatch

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"slices"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"
	"maunium.net/go/mautrix/pushrules"
)

// Room push rules and Beeper's mute account data represent the same control.
// The SDK keeps push rules in memory after sync; use its persisted copy at startup.
func (s *Dispatcher) roomPushRules(ctx context.Context) (*pushrules.PushRuleset, error) {
	cli := s.rt.Client()
	if rules := cli.PushRules.Load(); rules != nil {
		return rules, nil
	}
	var raw []byte
	err := cli.DB.QueryRow(ctx, `SELECT content FROM account_data WHERE user_id=? AND type='m.push_rules'`, cli.Account.UserID).Scan(&raw)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	} else if err != nil {
		return nil, err
	}
	var content pushrules.EventContent
	if err = json.Unmarshal(raw, &content); err != nil {
		return nil, fmt.Errorf("failed to read notification rules: %w", err)
	}
	return content.Ruleset, nil
}

func (s *Dispatcher) applyRoomMuteRules(ctx context.Context, states map[id.RoomID]roomAccountDataState, roomIDs []id.RoomID) error {
	rules, err := s.roomPushRules(ctx)
	if err != nil || rules == nil {
		return err
	}
	requested := make(map[id.RoomID]bool, len(roomIDs))
	for _, roomID := range roomIDs {
		requested[roomID] = true
	}
	for rawID, rule := range rules.Room.Map {
		roomID := id.RoomID(rawID)
		if len(requested) > 0 && !requested[roomID] {
			continue
		}
		if rule == nil || !rule.Enabled {
			continue
		}
		notifies := slices.ContainsFunc(rule.Actions, func(action *pushrules.PushAction) bool {
			return action != nil && (action.Action == pushrules.ActionNotify || action.Action == pushrules.ActionCoalesce)
		})
		if !notifies {
			state := states[roomID]
			state.IsMuted, state.MutedUntil = true, -1
			states[roomID] = state
		}
	}
	return nil
}

func (s *Dispatcher) setRoomMuteRule(ctx context.Context, roomID id.RoomID, muted bool) error {
	cli := s.rt.Client().Client
	if !muted {
		err := cli.DeletePushRule(ctx, "global", pushrules.RoomRule, string(roomID))
		if errors.Is(err, mautrix.MNotFound) {
			return nil
		}
		return err
	}
	if err := cli.PutPushRule(ctx, "global", pushrules.RoomRule, string(roomID), &mautrix.ReqPutPushRule{
		Actions: []pushrules.PushActionType{},
	}); err != nil {
		return err
	}
	// Replacing an existing disabled rule need not enable it automatically.
	_, err := cli.MakeRequest(ctx, http.MethodPut,
		cli.BuildClientURL("v3", "pushrules", "global", "room", roomID, "enabled"),
		map[string]bool{"enabled": true}, nil)
	return err
}

// Read back acknowledged settings, including partial writes after an error,
// so both the menu and the notification gateway use the server's actual state.
func (s *Dispatcher) refreshRoomMuteRules(ctx context.Context) error {
	cli := s.rt.Client()
	rules, err := cli.Client.GetPushRules(ctx)
	if err != nil {
		return err
	}
	raw, err := json.Marshal(pushrules.EventContent{Ruleset: rules})
	if err != nil {
		return err
	}
	cli.PushRules.Store(rules)
	data, err := cli.DB.AccountData.Put(ctx, cli.Account.UserID, event.AccountDataPushRules, raw)
	if err != nil {
		return err
	}
	s.events.enqueue(&jsoncmd.SyncComplete{AccountData: map[event.Type]*database.AccountData{event.AccountDataPushRules: data}})
	return nil
}
