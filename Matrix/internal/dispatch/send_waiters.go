package dispatch

import (
	"context"
	"errors"
	"strings"
	"sync"

	"go.mau.fi/gomuks/pkg/hicli"
	"go.mau.fi/gomuks/pkg/hicli/database"
	"go.mau.fi/gomuks/pkg/hicli/jsoncmd"
)

// sendWaiters lets a command wait for a message the SDK sends in the
// background, keyed by its transaction ID.
type sendWaiters struct {
	mu      sync.Mutex
	waiting map[string]chan error
}

func newSendWaiters() *sendWaiters {
	return &sendWaiters{waiting: make(map[string]chan error)}
}

// finish reports a background send's result to its waiter, if any.
func (w *sendWaiters) finish(complete *jsoncmd.SendComplete) {
	if complete == nil || complete.Event == nil {
		return
	}
	w.mu.Lock()
	done, ok := w.waiting[complete.Event.TransactionID]
	w.mu.Unlock()
	if ok {
		done <- complete.Error
	}
}

// wait returns once the server has accepted sent, or with its send error.
func (w *sendWaiters) wait(ctx context.Context, cli *hicli.HiClient, sent *database.Event) error {
	txnID := sent.TransactionID
	if txnID == "" {
		// The SDK answers some input, like unknown slash commands, with a
		// local-only notice instead of sending.
		return errors.New("message was not sent")
	}
	done := make(chan error, 1)
	w.mu.Lock()
	w.waiting[txnID] = done
	w.mu.Unlock()
	defer func() {
		w.mu.Lock()
		delete(w.waiting, txnID)
		w.mu.Unlock()
	}()
	// The SDK saves the result before reporting it, so a send that finished
	// before the waiter was registered shows in the database.
	if current, err := cli.DB.Event.GetByTransactionID(ctx, txnID); err == nil && current != nil {
		if !strings.HasPrefix(string(current.ID), "~") {
			return nil
		}
		if current.SendError != "" && current.SendError != "not sent" {
			return errors.New(current.SendError)
		}
	}
	select {
	case err := <-done:
		return err
	case <-ctx.Done():
		return errors.New("timed out sending the message")
	}
}
