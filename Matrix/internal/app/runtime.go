// Package app is the core's entry point for the FFI layer: it owns the gomuks
// runtime, routes the app's commands, and runs sync while the app is active.
package app

import (
	"context"
	"encoding/json"
	"time"

	"maunium.net/go/mautrix/id"

	"relay/core/internal/dispatch"
	"relay/core/internal/gomuksruntime"
	"relay/core/internal/wire"
)

type Config struct {
	StateDir string `json:"stateDir"`
}

type Runtime struct {
	cfg        Config
	rt         *gomuksruntime.Runtime
	dispatcher *dispatch.Dispatcher
	activity   *activityState
}

func New(cfg Config) (*Runtime, error) {
	rt, err := gomuksruntime.New(cfg.StateDir)
	if err != nil {
		return nil, err
	}
	return &Runtime{
		cfg:        cfg,
		rt:         rt,
		dispatcher: dispatch.New(rt),
		activity:   &activityState{attempted: make(map[id.SessionID]time.Time)},
	}, nil
}

// Start opens the database and the signed-in session, if any. Swift calls it
// once per process.
func (r *Runtime) Start(ctx context.Context) error {
	return r.rt.Start(ctx)
}

func (r *Runtime) Stop() {
	r.setActive(false)
	r.rt.Stop()
}

// Command holds the fields of the commands app handles itself. The dispatcher
// decodes its own commands' arguments from the same JSON object.
type Command struct {
	Action            string     `json:"action"`
	Active            bool       `json:"active"`
	RoomID            id.RoomID  `json:"roomID"`
	EventID           id.EventID `json:"eventID"`
	Text              string     `json:"text"`
	URL               string     `json:"url"`
	Path              string     `json:"path"`
	FileName          string     `json:"fileName"`
	MimeType          string     `json:"mimeType"`
	Pushkey           string     `json:"pushkey"`
	AppID             string     `json:"appID"`
	GatewayURL        string     `json:"gatewayURL"`
	DeviceDisplayName string     `json:"deviceDisplayName"`
}

// Execute runs one command; input is the command's whole JSON object.
func (r *Runtime) Execute(ctx context.Context, command Command, input json.RawMessage) (any, error) {
	switch command.Action {
	case "configure-mention-notifications":
		return wire.Success, r.configureMentionNotifications(ctx)
	case "active":
		r.setActive(command.Active)
		return wire.Success, nil
	case "opened-room":
		r.openRoom(command.RoomID)
		return wire.Success, nil
	case "local-asset":
		path, err := r.dispatcher.LocalAsset(ctx, command.URL)
		return map[string]any{"path": path}, err
	case "stage-upload":
		return r.dispatcher.StageUpload(command.Path, command.FileName, command.MimeType, r.cfg.StateDir)
	case "set-pusher", "remove-pusher":
		return r.updatePusher(ctx, command)
	case "notification-credentials":
		return r.notificationCredentials(ctx)
	case "push-preferences":
		return r.dispatcher.PushPreferences(ctx)
	case "notification-reply":
		return r.dispatcher.NotificationReply(ctx, command.RoomID, command.EventID, command.Text)
	case "logout":
		r.setActive(false)
		if err := r.rt.Logout(ctx); err != nil {
			return nil, err
		}
		return wire.Success, nil
	default:
		return r.dispatcher.Execute(ctx, command.Action, input)
	}
}

// OpenRealtime streams changes to send as JSON, replacing any earlier stream.
func (r *Runtime) OpenRealtime(connectionID uint64, send func([]byte)) {
	r.dispatcher.OpenRealtime(connectionID, func(payload any) {
		if raw, err := json.Marshal(payload); err == nil {
			send(raw)
		}
	})
}

func (r *Runtime) SubscribeRealtime(connectionID uint64, messageChatIDs []string) error {
	return r.dispatcher.SubscribeRealtime(connectionID, messageChatIDs)
}

func (r *Runtime) CloseRealtime(connectionID uint64) {
	r.dispatcher.CloseRealtime(connectionID)
}
