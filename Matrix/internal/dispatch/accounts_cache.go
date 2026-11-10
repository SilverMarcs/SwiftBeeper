package dispatch

import (
	"bytes"
	"slices"
	"sync"

	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

// accountsCache keeps the accounts parsed from one bridge state, so an
// unchanged bridge state isn't parsed again for every sync batch.
type accountsCache struct {
	mu       sync.Mutex
	userID   id.UserID
	content  []byte
	accounts []wire.Account
}

// get returns a copy of the accounts parsed from this user's content.
func (c *accountsCache) get(userID id.UserID, content []byte) ([]wire.Account, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.accounts == nil || c.userID != userID || !bytes.Equal(c.content, content) {
		return nil, false
	}
	return slices.Clone(c.accounts), true
}

func (c *accountsCache) set(userID id.UserID, content []byte, accounts []wire.Account) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.userID, c.content, c.accounts = userID, bytes.Clone(content), slices.Clone(accounts)
}
