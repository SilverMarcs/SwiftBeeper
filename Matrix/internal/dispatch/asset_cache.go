package dispatch

import (
	"context"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const (
	// The downloaded-media cache is kept under this size, dropping the files
	// used longest ago. It lives in the app group, which iOS never purges.
	maxAssetCacheBytes = int64(500 * 1024 * 1024)
	// Pruning trims to this share of the cap, so it doesn't run per download.
	assetCachePruneTarget = maxAssetCacheBytes * 8 / 10
	// How long one download may take, independent of any one caller.
	assetDownloadTimeout = 10 * time.Minute
	// Staged uploads that were never sent are dropped after this long.
	staleUploadAge = 24 * time.Hour
)

// assetCache shares downloads of the same media between concurrent callers
// and keeps the cache directory bounded.
type assetCache struct {
	mu      sync.Mutex
	flights map[string]*assetFlight
	pruning atomic.Bool
}

type assetFlight struct {
	done chan struct{}
	err  error
}

func newAssetCache() *assetCache {
	return &assetCache{flights: make(map[string]*assetFlight)}
}

// download runs fetch once per path at a time. Every caller waits for the
// same result, or for its own context. The download keeps its own deadline:
// a command gives up after the FFI's 20 seconds, which must stay short so the
// iOS app can close the store before it's suspended, but a slow download
// carries on and the next request for the same media joins it instead of
// starting over.
func (c *assetCache) download(ctx context.Context, path string, fetch func(context.Context) error) (string, error) {
	c.mu.Lock()
	flight, running := c.flights[path]
	if !running {
		flight = &assetFlight{done: make(chan struct{})}
		c.flights[path] = flight
		go func() {
			fetchCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), assetDownloadTimeout)
			defer cancel()
			flight.err = fetch(fetchCtx)
			c.mu.Lock()
			delete(c.flights, path)
			c.mu.Unlock()
			close(flight.done)
		}()
	}
	c.mu.Unlock()

	select {
	case <-flight.done:
		if flight.err != nil {
			return "", flight.err
		}
		return path, nil
	case <-ctx.Done():
		return "", ctx.Err()
	}
}

// touch marks a cached file as just used, for least-recently-used pruning.
func (c *assetCache) touch(path string) {
	now := time.Now()
	_ = os.Chtimes(path, now, now)
}

// pruneSoon trims the cache in the background, once at a time.
func (c *assetCache) pruneSoon(cacheDir, uploadDir string) {
	if !c.pruning.CompareAndSwap(false, true) {
		return
	}
	go func() {
		defer c.pruning.Store(false)
		pruneAssetCache(cacheDir)
		removeStaleUploads(uploadDir, staleUploadAge)
	}()
}

// pruneAssetCache deletes the least recently used files once the cache is
// over its cap, down to the prune target. Downloads in progress are skipped.
func pruneAssetCache(cacheDir string) {
	entries, err := os.ReadDir(cacheDir)
	if err != nil {
		return
	}
	type cachedFile struct {
		path     string
		size     int64
		lastUsed time.Time
	}
	files := make([]cachedFile, 0, len(entries))
	var total int64
	for _, entry := range entries {
		if entry.IsDir() || strings.HasPrefix(entry.Name(), "download-") {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		files = append(files, cachedFile{filepath.Join(cacheDir, entry.Name()), info.Size(), info.ModTime()})
		total += info.Size()
	}
	if total <= maxAssetCacheBytes {
		return
	}
	sort.Slice(files, func(i, j int) bool { return files[i].lastUsed.Before(files[j].lastUsed) })
	for _, file := range files {
		if total <= assetCachePruneTarget {
			return
		}
		if os.Remove(file.path) == nil {
			total -= file.size
		}
	}
}

// removeStaleUploads deletes staged uploads older than maxAge, which a send
// never picked up.
func removeStaleUploads(uploadDir string, maxAge time.Duration) {
	entries, err := os.ReadDir(uploadDir)
	if err != nil {
		return
	}
	cutoff := time.Now().Add(-maxAge)
	for _, entry := range entries {
		info, err := entry.Info()
		if err != nil || info.ModTime().After(cutoff) {
			continue
		}
		_ = os.RemoveAll(filepath.Join(uploadDir, entry.Name()))
	}
}
