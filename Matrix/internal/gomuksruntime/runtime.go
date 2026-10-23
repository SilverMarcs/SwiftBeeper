package gomuksruntime

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/rs/zerolog"
	"go.mau.fi/gomuks/pkg/hicli"
	"go.mau.fi/util/dbutil"
	"golang.org/x/net/http2"
	"maunium.net/go/mautrix"
)

// Runtime owns the on-device Matrix client and its SQLite store.
// The upstream gomuks web application and server are not part of Relay.
type Runtime struct {
	dataDir string
	client  *hicli.HiClient
	onEvent func(any)
}

func New(stateDir string) (*Runtime, error) {
	if stateDir == "" {
		return nil, fmt.Errorf("Matrix profile directory is required")
	}
	root, err := filepath.Abs(stateDir)
	if err != nil {
		return nil, err
	}
	// Preserve the existing profile layout and encryption pickle key.
	return &Runtime{dataDir: filepath.Join(root, "data")}, nil
}

func (r *Runtime) Start(ctx context.Context) error {
	if r.client != nil {
		return nil
	}
	if err := os.MkdirAll(r.dataDir, 0700); err != nil {
		return err
	}
	log := zerolog.Nop()
	rawDB, err := dbutil.NewFromConfig("gomuks", dbutil.Config{PoolConfig: dbutil.PoolConfig{
		Type:         "sqlite3-fk-wal",
		URI:          fmt.Sprintf("file:%s/gomuks.db?_txlock=immediate", r.dataDir),
		MaxOpenConns: 5, MaxIdleConns: 1,
	}}, dbutil.ZeroLogger(log))
	if err != nil {
		return fmt.Errorf("failed to open database: %w", err)
	}
	hicli.InitialDeviceDisplayName = "Relay"
	cli := hicli.New(rawDB, nil, log, []byte("meow"), r.emit)
	if transport, ok := cli.Client.Client.Transport.(*http.Transport); ok {
		transport.ForceAttemptHTTP2 = false
		h2, err := http2.ConfigureTransports(transport)
		if err != nil {
			cli.Stop()
			return err
		}
		h2.ReadIdleTimeout = 30 * time.Second
	}
	userID, err := cli.DB.Account.GetFirstUserID(ctx)
	if err == nil {
		err = cli.StartLocal(ctx, userID)
	}
	if err != nil {
		cli.Stop()
		return fmt.Errorf("failed to start Matrix client: %w", err)
	}
	r.client = cli
	return nil
}

func (r *Runtime) Stop() {
	if r.client != nil {
		r.client.Stop()
		r.client = nil
	}
}

func (r *Runtime) Client() *hicli.HiClient { return r.client }

// SetEventHandler routes sync events straight to their one in-process
// consumer. Set it before Start.
func (r *Runtime) SetEventHandler(handler func(any)) {
	r.onEvent = handler
}

func (r *Runtime) emit(evt any) {
	if r.onEvent != nil {
		r.onEvent(evt)
	}
}

func (r *Runtime) Logout(ctx context.Context) error {
	_, err := r.client.Client.Logout(ctx)
	if err != nil && !errors.Is(err, mautrix.MUnknownToken) {
		return err
	}
	r.Stop()
	if err = os.RemoveAll(r.dataDir); err != nil {
		return err
	}
	// Older builds created an upstream cache directory beside the database.
	if err = os.RemoveAll(filepath.Join(filepath.Dir(r.dataDir), "cache")); err != nil {
		return err
	}
	if err = r.Start(context.Background()); err != nil {
		return err
	}
	r.emit(r.client.State())
	r.emit(r.client.SyncStatus.Load())
	return nil
}

func (r *Runtime) StateDir() string {
	return r.dataDir
}
