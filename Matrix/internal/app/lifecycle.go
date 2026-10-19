package app

import (
	"context"
	"fmt"
	"sync"
	"time"

	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
	"maunium.net/go/mautrix/id"
)

type MobileCommand struct {
	Action            string    `json:"action"`
	Active            bool      `json:"active"`
	RoomID            id.RoomID `json:"roomID"`
	URL               string    `json:"url"`
	Path              string    `json:"path"`
	FileName          string    `json:"fileName"`
	MimeType          string    `json:"mimeType"`
	Pushkey           string    `json:"pushkey"`
	AppID             string    `json:"appID"`
	GatewayURL        string    `json:"gatewayURL"`
	DeviceDisplayName string    `json:"deviceDisplayName"`
}

type mobileState struct {
	mu              sync.Mutex
	cancel          context.CancelFunc
	context         context.Context
	roomID          id.RoomID
	roomCancel      context.CancelFunc
	generation      uint64
	scope           string
	versionsChecked bool
	attempted       map[id.SessionID]time.Time
}

var mobileStates sync.Map

func (r *Runtime) mobile() *mobileState {
	value, _ := mobileStates.LoadOrStore(r, &mobileState{attempted: make(map[id.SessionID]time.Time)})
	return value.(*mobileState)
}

func (r *Runtime) MobileExecute(ctx context.Context, command MobileCommand) (any, error) {
	switch command.Action {
	case "active":
		r.setMobileActive(command.Active)
		return map[string]any{"success": true}, nil
	case "opened-room":
		r.openMobileRoom(command.RoomID)
		return map[string]any{"success": true}, nil
	case "local-asset":
		path, err := r.dispatcher.MobileAsset(ctx, command.URL)
		return map[string]any{"path": path}, err
	case "stage-upload":
		return r.dispatcher.MobileStageUpload(ctx, command.Path, command.FileName, command.MimeType, r.cfg.StateDir)
	case "set-pusher", "remove-pusher":
		return r.updatePusher(ctx, command)
	case "notification-credentials":
		return r.notificationCredentials(ctx)
	case "push-preferences":
		return r.dispatcher.PushPreferences(ctx)
	case "logout":
		r.setMobileActive(false)
		err := r.rt.SubmitJSONCommand(ctx, jsoncmd.ReqLogout, nil, nil)
		return map[string]any{"success": err == nil}, err
	default:
		return nil, fmt.Errorf("unknown local command")
	}
}

// Only actual background suspension pauses sync. Negotiation is reused within
// this login; sync itself continues from the SDK's persisted next_batch token.
func (r *Runtime) setMobileActive(active bool) {
	state := r.mobile()
	state.mu.Lock()
	cli := r.rt.Client()
	if !active {
		if state.cancel != nil {
			state.cancel()
		}
		if state.roomCancel != nil {
			state.roomCancel()
		}
		state.cancel, state.context, state.roomCancel = nil, nil, nil
		state.generation++
		state.mu.Unlock()
		if cli != nil {
			cli.PauseLocalSync()
		}
		return
	}
	if state.cancel != nil || cli == nil || cli.Account == nil || !cli.State().IsVerified {
		state.mu.Unlock()
		return
	}
	scope := string(cli.Account.UserID) + "|" + string(cli.Account.DeviceID) + "|" + cli.Account.HomeserverURL
	if scope != state.scope {
		state.scope, state.versionsChecked = scope, false
		clear(state.attempted)
	}
	ctx, cancel := context.WithCancel(context.Background())
	state.cancel, state.context = cancel, ctx
	checked := state.versionsChecked
	state.mu.Unlock()
	go func() {
		delay := time.Second
		for ctx.Err() == nil {
			attempt, stop := context.WithTimeout(ctx, 15*time.Second)
			var err error
			if !checked {
				err = cli.CheckServerVersions(attempt)
			}
			if err == nil {
				checked = true
				state.mu.Lock()
				state.versionsChecked = true
				state.mu.Unlock()
				if cli.KeyBackupVersion == "" {
					if latest, backupErr := cli.Client.GetKeyBackupLatestVersion(attempt); backupErr == nil {
						cli.KeyBackupVersion = latest.Version
					}
				}
				if ctx.Err() == nil {
					go cli.SyncLocalContext(ctx)
					r.startOpenRoomWork()
				}
			}
			stop()
			if err == nil {
				return
			}
			select {
			case <-ctx.Done():
				return
			case <-time.After(delay):
			}
			if delay < 30*time.Second {
				delay *= 2
			}
		}
	}()
}

func (r *Runtime) openMobileRoom(room id.RoomID) {
	state := r.mobile()
	state.mu.Lock()
	if state.roomID == room {
		state.mu.Unlock()
		return
	}
	if state.roomCancel != nil {
		state.roomCancel()
	}
	state.roomID, state.roomCancel = room, nil
	state.generation++
	state.mu.Unlock()
	r.startOpenRoomWork()
}

// One bounded task for the selected room. Reads and pagination never restart
// this work. A real foreground resume can retry failed sessions after cooldown.
func (r *Runtime) startOpenRoomWork() {
	state := r.mobile()
	state.mu.Lock()
	if state.roomID == "" || state.context == nil || state.context.Err() != nil || state.roomCancel != nil {
		state.mu.Unlock()
		return
	}
	room := state.roomID
	generation := state.generation
	ctx, cancel := context.WithTimeout(state.context, 20*time.Second)
	state.roomCancel = cancel
	state.mu.Unlock()
	go func() {
		defer cancel()
		defer func() {
			state.mu.Lock()
			if state.generation == generation {
				state.roomCancel = nil
			}
			state.mu.Unlock()
		}()
		cli := r.rt.Client()
		if cli == nil || cli.Account == nil {
			return
		}
		cached, err := r.dispatcher.RecentRoomMessages(ctx, room, 40)
		if err != nil {
			return
		}
		r.dispatcher.RefreshPreview(ctx, room, cached)

		// Requeue at most four sessions which the SDK already checked. The SDK
		// owns the requests and decryption; no parallel backup download loop.
		if cli.KeyBackupKey == nil || cli.KeyBackupVersion == "" {
			return
		}
		var sessions []id.SessionID
		seen := make(map[id.SessionID]bool)
		for _, evt := range cached {
			if evt.DecryptionError != "" && evt.MegolmSessionID != "" && !seen[evt.MegolmSessionID] {
				seen[evt.MegolmSessionID] = true
				sessions = append(sessions, evt.MegolmSessionID)
			}
		}
		retried := 0

		now := time.Now()
		for _, session := range sessions {
			if retried >= 4 {
				break
			}
			state.mu.Lock()
			last := state.attempted[session]
			if now.Sub(last) < time.Minute {
				state.mu.Unlock()
				continue
			}
			state.attempted[session] = now
			for key, when := range state.attempted {
				if now.Sub(when) > 10*time.Minute {
					delete(state.attempted, key)
				}
			}
			state.mu.Unlock()
			result, err := cli.DB.Exec(ctx, `UPDATE session_request SET backup_checked=false, request_sent=false WHERE room_id=? AND session_id=? AND backup_checked=true`, room, session)
			if err == nil {
				if changed, _ := result.RowsAffected(); changed > 0 {
					retried++
				}
			}

		}
		if retried > 0 {
			cli.WakeupRequestQueue()
		}
	}()
}
