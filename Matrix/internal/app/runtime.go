package app

import (
	"context"
	"encoding/json"
	"maunium.net/go/mautrix/id"
	"time"

	"relay/core/internal/dispatch"
	"relay/core/internal/gomuksruntime"
)

type Config struct {
	StateDir string `json:"stateDir"`
}

type Runtime struct {
	cfg         Config
	rt          *gomuksruntime.Runtime
	dispatcher  *dispatch.Dispatcher
	mobileState *mobileState
}

func New(input Config) (*Runtime, error) {
	cfg := input

	rt, err := gomuksruntime.New(cfg.StateDir)
	if err != nil {
		return nil, err
	}
	dispatcher := dispatch.New(rt)
	return &Runtime{cfg: cfg, rt: rt, dispatcher: dispatcher, mobileState: &mobileState{attempted: make(map[id.SessionID]time.Time)}}, nil
}

// Start opens the database and the signed-in session, if any. Swift calls it
// once per process.
func (r *Runtime) Start(ctx context.Context) error {
	return r.rt.Start(ctx)
}

func (r *Runtime) Stop() {
	r.setMobileActive(false)
	r.rt.Stop()
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
