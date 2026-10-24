package app

import (
	"context"
	"sync"
	"time"

	"maunium.net/go/mautrix/id"
)

// Sync runs only while the app is active, and the open room gets one bounded
// round of catch-up work: a preview refresh and key re-requests.

const (
	openRoomScanLimit     = 40
	maxSessionRetries     = 4
	sessionRetryCooldown  = time.Minute
	sessionRetryRetention = 10 * time.Minute
)

type activityState struct {
	mu sync.Mutex
	// cancel and context belong to the current active period; nil while
	// inactive.
	cancel  context.CancelFunc
	context context.Context
	roomID  id.RoomID
	// roomCancel stops the open room's work; nil when none is running.
	roomCancel context.CancelFunc
	// generation changes whenever running room work becomes stale.
	generation uint64
	// scope identifies the login versionsChecked and attempted belong to.
	scope           string
	versionsChecked bool
	// When each undecryptable session was last re-requested.
	attempted map[id.SessionID]time.Time
}

// setActive starts or pauses sync. Only actual background suspension pauses
// it. Negotiation is reused within this login; sync itself continues from the
// SDK's persisted next_batch token.
func (r *Runtime) setActive(active bool) {
	state := r.activity
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
		// Also stops the sync gomuks starts itself right after verification,
		// which the context above doesn't own.
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
	// Retry the server version check with backoff, then start sync.
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

func (r *Runtime) openRoom(room id.RoomID) {
	state := r.activity
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

// startOpenRoomWork runs one bounded task for the selected room while the app
// is active. Reads and pagination never restart this work. A real foreground
// resume can retry failed sessions after a cooldown.
func (r *Runtime) startOpenRoomWork() {
	state := r.activity
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
		cached, err := r.dispatcher.RecentRoomMessages(ctx, room, openRoomScanLimit)
		if err != nil {
			return
		}
		r.dispatcher.RefreshPreview(ctx, room, cached)

		// Requeue a few sessions which the SDK already checked. The SDK owns
		// the requests and decryption; no parallel backup download loop.
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
			if retried >= maxSessionRetries {
				break
			}
			if !r.claimSessionRetry(session, now) {
				continue
			}
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

// claimSessionRetry records a retry of session at now, unless one ran within
// the cooldown. It also forgets retries old enough not to matter.
func (r *Runtime) claimSessionRetry(session id.SessionID, now time.Time) bool {
	state := r.activity
	state.mu.Lock()
	defer state.mu.Unlock()
	if now.Sub(state.attempted[session]) < sessionRetryCooldown {
		return false
	}
	state.attempted[session] = now
	for key, when := range state.attempted {
		if now.Sub(when) > sessionRetryRetention {
			delete(state.attempted, key)
		}
	}
	return true
}
