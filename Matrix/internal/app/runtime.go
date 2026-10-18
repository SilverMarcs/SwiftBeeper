package app

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"sync"

	"relay/core/internal/config"
	"relay/core/internal/dispatch"
	"relay/core/internal/gomuksruntime"
)

type Request struct {
	Method  string              `json:"method"`
	URL     string              `json:"url"`
	Headers map[string][]string `json:"headers,omitempty"`
	BodyB64 string              `json:"body_base64,omitempty"`
}

type Response struct {
	Status  int                 `json:"status"`
	Headers map[string][]string `json:"headers,omitempty"`
	BodyB64 string              `json:"body_base64,omitempty"`
}

type Config struct {
	AccessToken         string `json:"accessToken"`
	StateDir            string `json:"stateDir"`
	ManageSecret        string `json:"manageSecret"`
	BeeperHomeserverURL string `json:"beeperHomeserverUrl"`
}

type Runtime struct {
	cfg        config.Config
	rt         *gomuksruntime.Runtime
	dispatcher *dispatch.Dispatcher
	handler    http.Handler
	mu         sync.Mutex
	started    bool
}

func New(input Config) (*Runtime, error) {
	cfg := config.Config{AccessToken: input.AccessToken, ManageSecret: input.ManageSecret,
		StateDir: input.StateDir, MatrixHomeserverURL: input.BeeperHomeserverURL}
	rt, err := gomuksruntime.New(cfg)
	if err != nil {
		return nil, err
	}
	dispatcher := dispatch.New(cfg, rt)
	return &Runtime{cfg: cfg, rt: rt, dispatcher: dispatcher, handler: dispatcher.Handler()}, nil
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

func (r *Runtime) Handle(ctx context.Context, request Request) (Response, error) {
	if err := r.Start(ctx); err != nil {
		return Response{}, err
	}
	body, err := base64.StdEncoding.DecodeString(request.BodyB64)
	if err != nil {
		return Response{}, fmt.Errorf("invalid local request body")
	}
	method := strings.ToUpper(strings.TrimSpace(request.Method))
	if method == "" {
		method = http.MethodGet
	}
	local, err := http.NewRequestWithContext(ctx, method, request.URL, bytes.NewReader(body))
	if err != nil {
		return Response{}, err
	}
	if local.URL.Host != "relay.local.invalid" {
		return Response{}, fmt.Errorf("invalid local transport host")
	}
	for key, values := range request.Headers {
		for _, value := range values {
			local.Header.Add(key, value)
		}
	}
	output := &localResponse{header: make(http.Header)}
	r.handler.ServeHTTP(output, local)
	if output.status == 0 {
		output.status = http.StatusOK
	}
	return Response{Status: output.status, Headers: output.header, BodyB64: base64.StdEncoding.EncodeToString(output.body.Bytes())}, nil
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
	})
}

// localResponse adapts the current message handlers to the C bridge in memory.
// Requests and responses stay inside this process.
type localResponse struct {
	header http.Header
	status int
	body   bytes.Buffer
}

func (r *localResponse) Header() http.Header { return r.header }
func (r *localResponse) WriteHeader(status int) {
	if r.status == 0 {
		r.status = status
	}
}
func (r *localResponse) Write(data []byte) (int, error) {
	if r.status == 0 {
		r.status = http.StatusOK
	}
	return r.body.Write(data)
}
