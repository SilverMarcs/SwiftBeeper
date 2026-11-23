package dispatch

import (
	"context"
	"encoding/json"
	"log"
	"strings"
	"sync"

	"maunium.net/go/mautrix/event"
)

// shortcodeKey is the content key bridges name a custom emoji reaction with,
// such as ":party_parrot:".
const shortcodeKey = "com.beeper.reaction.shortcode"

// reactionContent is a reaction's key and, for a bridged custom emoji, its
// shortcode and the bridge it came from.
type reactionContent struct {
	key       string
	shortcode string
	// The bridge's own reaction field, such as "fi.mau.slack.reaction", so a
	// shortcode only resolves to an image from the same network.
	bridge string
}

// customEmojiName is a custom emoji's shortcode on one bridge.
type customEmojiName struct {
	bridge    string
	shortcode string
}

func parseReactionContent(content json.RawMessage) (reactionContent, bool) {
	var fields map[string]json.RawMessage
	if json.Unmarshal(content, &fields) != nil {
		return reactionContent{}, false
	}
	var relatesTo event.RelatesTo
	if json.Unmarshal(fields["m.relates_to"], &relatesTo) != nil {
		return reactionContent{}, false
	}
	parsed := reactionContent{key: strings.TrimSpace(relatesTo.Key)}
	if raw, ok := fields[shortcodeKey]; ok {
		_ = json.Unmarshal(raw, &parsed.shortcode)
	}
	for name := range fields {
		if strings.HasPrefix(name, "fi.mau.") && strings.HasSuffix(name, ".reaction") {
			parsed.bridge = name
			break
		}
	}
	return parsed, parsed.key != ""
}

// isShortcodeReactionKey reports whether a key is a bare ":shortcode:",
// which bridges send when they don't have the custom emoji's image.
func isShortcodeReactionKey(key string) bool {
	return len(key) > 2 && strings.HasPrefix(key, ":") && strings.HasSuffix(key, ":") &&
		!strings.ContainsAny(key, " \n\t")
}

// unresolvedName is the custom emoji a reaction names without its image.
func (r reactionContent) unresolvedName() (customEmojiName, bool) {
	if !isShortcodeReactionKey(r.key) {
		return customEmojiName{}, false
	}
	shortcode := r.shortcode
	if shortcode == "" {
		shortcode = r.key
	}
	return customEmojiName{bridge: r.bridge, shortcode: shortcode}, true
}

// customEmojiCache maps bridged custom emoji to their images. Bridges such as
// Slack's send a custom emoji reaction as its mxc:// image when they have it
// and as the bare ":shortcode:" when they don't, both with the shortcode in
// com.beeper.reaction.shortcode. A shortcode-only reaction takes the newest
// image any reaction from the same bridge carried for that shortcode, in any
// room: the same emoji is rarely reacted with in the same room both ways.
// Each miss reads only the reactions stored since the last read. The zero
// value is ready to use.
type customEmojiCache struct {
	mu     sync.Mutex
	images map[customEmojiName]string
	// The newest event row read.
	lastRowID int64
}

// customEmojiImagesQuery finds the reactions in a range of rows that carry a
// custom emoji's image, oldest first so newer images replace older ones.
const customEmojiImagesQuery = `
	SELECT coalesce(decrypted, content) FROM event
	WHERE rowid > ? AND rowid <= ? AND coalesce(decrypted_type, type) = 'm.reaction' AND redacted_by IS NULL
	  AND json_extract(coalesce(decrypted, content), '$."m.relates_to".key') LIKE 'mxc://%'
	  AND json_extract(coalesce(decrypted, content), '$."` + shortcodeKey + `"') IS NOT NULL
	ORDER BY rowid`

// resolveCustomEmoji returns the image a custom emoji's name resolves to,
// first reading the reactions stored since the last read when it has none.
func (s *Dispatcher) resolveCustomEmoji(ctx context.Context, name customEmojiName) (string, bool) {
	c := &s.customEmoji
	c.mu.Lock()
	defer c.mu.Unlock()
	if image, ok := c.images[name]; ok {
		return image, true
	}
	if err := s.readCustomEmojiImages(ctx, c); err != nil {
		log.Printf("relay: failed to read custom emoji: %v", err)
	}
	image, ok := c.images[name]
	return image, ok
}

// readCustomEmojiImages adds the images of reactions stored since the last
// read. The caller holds c.mu.
func (s *Dispatcher) readCustomEmojiImages(ctx context.Context, c *customEmojiCache) error {
	db := s.rt.Client().DB
	var newestRowID int64
	if err := db.QueryRow(ctx, `SELECT coalesce(max(rowid), 0) FROM event`).Scan(&newestRowID); err != nil {
		return err
	}
	if newestRowID <= c.lastRowID {
		return nil
	}
	rows, err := db.Query(ctx, customEmojiImagesQuery, c.lastRowID, newestRowID)
	if err != nil {
		return err
	}
	defer rows.Close()
	if c.images == nil {
		c.images = make(map[customEmojiName]string)
	}
	for rows.Next() {
		var content []byte
		if err = rows.Scan(&content); err != nil {
			return err
		}
		parsed, ok := parseReactionContent(content)
		if !ok || parsed.shortcode == "" || !strings.HasPrefix(parsed.key, "mxc://") {
			continue
		}
		c.images[customEmojiName{bridge: parsed.bridge, shortcode: parsed.shortcode}] = parsed.key
	}
	if err = rows.Err(); err != nil {
		return err
	}
	c.lastRowID = newestRowID
	return nil
}

// resolvedReaction is the key a reaction is shown and grouped under (a
// shortcode-only custom emoji's image when one is known) and its shortcode.
func (s *Dispatcher) resolvedReaction(ctx context.Context, reaction reactionContent) (key, shortcode string) {
	name, ok := reaction.unresolvedName()
	if !ok {
		return reaction.key, reaction.shortcode
	}
	if image, ok := s.resolveCustomEmoji(ctx, name); ok {
		return image, name.shortcode
	}
	return reaction.key, name.shortcode
}
