package app

import (
	"context"
	"encoding/json"
	"maunium.net/go/mautrix/id"
	"sync"
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
	mu          sync.Mutex
	started     bool
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

func (r *Runtime) Start(ctx context.Context) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.started {
		return nil
	}
	if err := r.rt.Start(ctx); err != nil {
		return err
	}
	r.started = true
	return nil
}

func (r *Runtime) Stop() {
	r.setMobileActive(false)
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.started {
		r.rt.Stop()
		r.started = false
	}
}

func (r *Runtime) OpenRealtime(send func(json.RawMessage) error) (*dispatch.RealtimeConnection, error) {
	if err := r.Start(context.Background()); err != nil {
		return nil, err
	}
	return r.dispatcher.OpenRealtime(func(payload any) error {
		raw, err := json.Marshal(payload)
		if err != nil {
			return err
		}
		return send(raw)
	}), nil
}
