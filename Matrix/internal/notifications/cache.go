package notifications

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"

	"maunium.net/go/mautrix"
)

// cache keeps the last names, avatar URLs and avatar thumbnails a push
// resolved, so a slow lookup on a later push still shows them. Files live in
// the extension's Caches directory, which the system may purge.
type cache struct{ dir string }

func newCache(dir string, user string) cache {
	if dir == "" {
		return cache{}
	}
	return cache{dir: filepath.Join(dir, "notifications", hash(user))}
}

// remember stores value after a successful lookup. After a failed one it
// loads the last stored value into value instead. A missing state event or
// profile is a successful lookup of nothing.
func (c cache) remember(kind, key string, value any, err error) {
	if err == nil || errors.Is(err, mautrix.MNotFound) {
		if data, err := json.Marshal(value); err == nil {
			c.write(kind, key, data)
		}
	} else if data := c.read(kind, key); data != nil {
		_ = json.Unmarshal(data, value)
	}
}

func (c cache) read(kind, key string) []byte {
	if c.dir == "" {
		return nil
	}
	data, _ := os.ReadFile(filepath.Join(c.dir, kind, hash(key)))
	return data
}

// write replaces the entry atomically, since pushes may resolve concurrently.
func (c cache) write(kind, key string, data []byte) {
	if c.dir == "" {
		return
	}
	dir := filepath.Join(c.dir, kind)
	if os.MkdirAll(dir, 0o700) != nil {
		return
	}
	file, err := os.CreateTemp(dir, "*.tmp")
	if err != nil {
		return
	}
	_, err = file.Write(data)
	if closeErr := file.Close(); err == nil && closeErr == nil {
		err = os.Rename(file.Name(), filepath.Join(dir, hash(key)))
	}
	if err != nil {
		_ = os.Remove(file.Name())
	}
}

func hash(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:16])
}
