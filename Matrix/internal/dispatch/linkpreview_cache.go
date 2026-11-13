package dispatch

import (
	"context"
	"errors"
	"net/http"
	"sync"
	"time"

	"maunium.net/go/mautrix"

	"relay/core/internal/wire"
)

const (
	// Previews of pages change rarely; a session rarely outlives this.
	linkPreviewTTL = 6 * time.Hour
	// A page the homeserver couldn't preview is retried after this long.
	linkPreviewFailureTTL   = time.Hour
	linkPreviewFetchTimeout = 15 * time.Second
	// Scrolling through a chat full of links shouldn't flood the homeserver.
	linkPreviewConcurrentFetches = 4
	linkPreviewCacheLimit        = 512
)

// linkPreviewCache holds the homeserver's previews by link, empty ones
// included, and shares one fetch among concurrent requests for a link. Each
// fetch runs on its own deadline, so a caller giving up doesn't fail the
// others waiting on it. The zero value is ready to use.
type linkPreviewCache struct {
	mu       sync.Mutex
	entries  map[string]linkPreviewEntry
	order    []string
	inflight map[string]*linkPreviewFetch
	slots    chan struct{}
}

type linkPreviewEntry struct {
	preview *wire.LinkPreview
	expires time.Time
}

type linkPreviewFetch struct {
	done    chan struct{}
	preview *wire.LinkPreview
	err     error
}

// get returns the cached preview of link, fetching it on a miss. A nil
// preview means the page has none; an error means the fetch should be
// retried later.
func (c *linkPreviewCache) get(
	ctx context.Context,
	link string,
	fetch func(context.Context, string) (*wire.LinkPreview, error),
) (*wire.LinkPreview, error) {
	c.mu.Lock()
	if entry, ok := c.entries[link]; ok && time.Now().Before(entry.expires) {
		c.mu.Unlock()
		return entry.preview, nil
	}
	if c.inflight == nil {
		c.entries = make(map[string]linkPreviewEntry)
		c.inflight = make(map[string]*linkPreviewFetch)
		c.slots = make(chan struct{}, linkPreviewConcurrentFetches)
	}
	pending, ok := c.inflight[link]
	if !ok {
		pending = &linkPreviewFetch{done: make(chan struct{})}
		c.inflight[link] = pending
		go c.run(link, pending, fetch)
	}
	c.mu.Unlock()

	select {
	case <-pending.done:
		return pending.preview, pending.err
	case <-ctx.Done():
		return nil, ctx.Err()
	}
}

func (c *linkPreviewCache) run(link string, pending *linkPreviewFetch, fetch func(context.Context, string) (*wire.LinkPreview, error)) {
	ctx, cancel := context.WithTimeout(context.Background(), linkPreviewFetchTimeout)
	defer cancel()
	ttl := linkPreviewTTL
	select {
	case c.slots <- struct{}{}:
		pending.preview, pending.err = fetch(ctx, link)
		<-c.slots
	case <-ctx.Done():
		pending.err = ctx.Err()
	}
	if pending.err != nil && isPermanentPreviewFailure(pending.err) {
		// The homeserver answered that it can't preview the page, such as
		// one that's unreachable or isn't HTML: remember that it has none.
		pending.preview, pending.err = nil, nil
		ttl = linkPreviewFailureTTL
	}

	c.mu.Lock()
	delete(c.inflight, link)
	if pending.err == nil {
		if _, exists := c.entries[link]; !exists {
			c.order = append(c.order, link)
		}
		c.entries[link] = linkPreviewEntry{preview: pending.preview, expires: time.Now().Add(ttl)}
		for len(c.order) > linkPreviewCacheLimit {
			delete(c.entries, c.order[0])
			c.order = c.order[1:]
		}
	}
	c.mu.Unlock()
	close(pending.done)
}

// isPermanentPreviewFailure reports an error response from the homeserver,
// other than rate limiting; network failures and timeouts are transient.
func isPermanentPreviewFailure(err error) bool {
	var httpErr mautrix.HTTPError
	if !errors.As(err, &httpErr) || httpErr.Response == nil {
		return false
	}
	status := httpErr.Response.StatusCode
	return status >= 400 && status != http.StatusTooManyRequests
}
