package dispatch

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"sync"
	"time"

	"go.mau.fi/gomuks/pkg/hicli"
	"go.mau.fi/gomuks/pkg/hicli/database"
	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

// Bookmarks are Beeper's own: one event per bookmarked message in the
// account's private, encrypted Bookmarks room, relating to the message with
// Beeper's relation key. Removing a bookmark redacts its event. Other Beeper
// apps read and write the same room, so bookmarks sync with them; nothing
// reaches the chat's network.
const (
	bookmarksRoomID      = id.RoomID("!bookmarks:" + hungryservServerName)
	bookmarkEventType    = "com.beeper.bookmark"
	bookmarkRelationType = "com.beeper.bookmark"
	beeperRelatesToKey   = "com.beeper.relates_to"
	bookmarkPageSize     = 100
	bookmarkFetchLimit   = 50
	// How far back opening a bookmark pages a chat for its message.
	bookmarkHistoryPages = 20
)

var errBookmarksUnavailable = errors.New("Bookmarks need a Beeper account")

type bookmarkRelation struct {
	EventID id.EventID `json:"event_id"`
	RoomID  id.RoomID  `json:"room_id"`
	RelType string     `json:"rel_type"`
}

// bookmarkState remembers the bookmark events this session redacted before
// sync reports them, and runs one restore at a time.
type bookmarkState struct {
	mu        sync.Mutex
	removed   map[id.EventID]bool
	restoring sync.Mutex
}

func (b *bookmarkState) markRemoved(eventIDs []id.EventID) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.removed == nil {
		b.removed = make(map[id.EventID]bool)
	}
	for _, eventID := range eventIDs {
		b.removed[eventID] = true
	}
}

func (b *bookmarkState) isRemoved(eventID id.EventID) bool {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.removed[eventID]
}

// restoreBookmarks reads the Bookmarks room back to its start, since sync only
// delivers its newest events and bookmarks made in other Beeper apps before
// this login are older. The SDK stores the pages and remembers reaching the
// start, so once done this is a single read.
func (s *Dispatcher) restoreBookmarks(ctx context.Context) error {
	s.bookmarks.restoring.Lock()
	defer s.bookmarks.restoring.Unlock()
	cli := s.rt.Client()
	room, err := cli.DB.Room.Get(ctx, bookmarksRoomID)
	if err != nil {
		return fmt.Errorf("failed to read bookmarks: %w", err)
	} else if room == nil {
		return errBookmarksUnavailable
	} else if room.PrevBatch == database.PrevBatchPaginationComplete {
		return nil
	}
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	for {
		resp, err := cli.PaginateServer(ctx, bookmarksRoomID, bookmarkPageSize, false)
		switch {
		case errors.Is(err, hicli.ErrPaginationAlreadyInProgress):
			return nil
		case err != nil:
			return fmt.Errorf("failed to load bookmarks: %w", err)
		case !resp.HasMore:
			return nil
		}
	}
}

type storedBookmark struct {
	eventID  id.EventID
	relation bookmarkRelation
}

// loadBookmarks reads the user's live bookmarks of messages in roomID, most
// recently bookmarked first. Undecrypted events count once their keys arrive.
func (s *Dispatcher) loadBookmarks(ctx context.Context, roomID id.RoomID, messageID id.EventID) ([]storedBookmark, error) {
	cli := s.rt.Client()
	query := `SELECT event_id, json_extract(COALESCE(decrypted, content), '$."` + beeperRelatesToKey + `"')
		FROM event
		WHERE room_id=? AND sender=? AND (type=? OR decrypted_type=?)
		AND (redacted_by IS NULL OR redacted_by='') AND event_id NOT LIKE '~%'
		AND json_extract(COALESCE(decrypted, content), '$."` + beeperRelatesToKey + `".room_id')=?`
	args := []any{bookmarksRoomID, cli.Account.UserID, bookmarkEventType, bookmarkEventType, roomID}
	if messageID != "" {
		query += ` AND json_extract(COALESCE(decrypted, content), '$."` + beeperRelatesToKey + `".event_id')=?`
		args = append(args, messageID)
	}
	query += ` ORDER BY timestamp DESC, rowid DESC`
	rows, err := cli.DB.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("failed to read bookmarks: %w", err)
	}
	defer rows.Close()
	var bookmarks []storedBookmark
	for rows.Next() {
		var bookmark storedBookmark
		var relation []byte
		if err = rows.Scan(&bookmark.eventID, &relation); err != nil {
			return nil, err
		}
		if json.Unmarshal(relation, &bookmark.relation) != nil ||
			bookmark.relation.RelType != bookmarkRelationType || bookmark.relation.EventID == "" ||
			s.bookmarks.isRemoved(bookmark.eventID) {
			continue
		}
		bookmarks = append(bookmarks, bookmark)
	}
	return bookmarks, rows.Err()
}

// setMessageBookmark adds or removes the bookmark of one message.
func (s *Dispatcher) setMessageBookmark(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID     string `json:"chatID"`
		MessageID  string `json:"messageID"`
		Bookmarked *bool  `json:"bookmarked"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	roomID, eventID, err := messageTarget(req.ChatID, req.MessageID)
	if err != nil {
		return nil, err
	}
	if req.Bookmarked == nil {
		return nil, errors.New("bookmarked is required")
	}
	if err = s.restoreBookmarks(ctx); err != nil {
		return nil, err
	}
	existing, err := s.loadBookmarks(ctx, roomID, eventID)
	if err != nil {
		return nil, err
	}
	relation := bookmarkRelation{EventID: eventID, RoomID: roomID, RelType: bookmarkRelationType}
	cli := s.rt.Client()
	if *req.Bookmarked {
		if len(existing) > 0 {
			return wire.Success, nil
		}
		content := map[string]any{beeperRelatesToKey: relation}
		evtType := event.Type{Type: bookmarkEventType, Class: event.MessageEventType}
		sent, err := cli.Send(ctx, bookmarksRoomID, evtType, content, false, true)
		if err != nil {
			return nil, fmt.Errorf("failed to bookmark message: %w", err)
		}
		// A synchronous send reports its failure only on the event, which
		// keeps its local ID.
		if sent.ID == "" || strings.HasPrefix(string(sent.ID), "~") {
			return nil, fmt.Errorf("failed to bookmark message: %s", sent.SendError)
		}
		return wire.Success, nil
	}
	// Each duplicate another app left goes too, as the message has no
	// bookmark until all of them do.
	var removed []id.EventID
	for _, bookmark := range existing {
		// The relation survives the redaction, so other apps can tell which
		// message lost its bookmark without the redacted content.
		_, err = cli.Client.RedactEvent(ctx, bookmarksRoomID, bookmark.eventID, mautrix.ReqRedact{
			Extra: map[string]any{beeperRelatesToKey: relation},
		})
		if err != nil && !errors.Is(err, mautrix.MNotFound) {
			s.bookmarks.markRemoved(removed)
			return nil, fmt.Errorf("failed to remove bookmark: %w", err)
		}
		removed = append(removed, bookmark.eventID)
	}
	s.bookmarks.markRemoved(removed)
	return wire.Success, nil
}

// listMessageBookmarks returns the chat's bookmarked message IDs, most
// recently bookmarked first, and with includeMessages the messages too. A
// message the device never stored is fetched from the server.
func (s *Dispatcher) listMessageBookmarks(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		ChatID          string `json:"chatID"`
		IncludeMessages bool   `json:"includeMessages"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	chatID, err := required(req.ChatID, "chatID")
	if err != nil {
		return nil, err
	}
	output := wire.ListMessageBookmarksOutput{MessageIDs: []string{}}
	if err = s.restoreBookmarks(ctx); errors.Is(err, errBookmarksUnavailable) {
		return output, nil
	} else if err != nil {
		return nil, err
	}
	output.Available = true
	roomID := id.RoomID(chatID)
	bookmarks, err := s.loadBookmarks(ctx, roomID, "")
	if err != nil {
		return nil, err
	}
	seen := make(map[string]bool, len(bookmarks))
	var messageIDs []string
	for _, bookmark := range bookmarks {
		if messageID := string(bookmark.relation.EventID); !seen[messageID] {
			seen[messageID] = true
			messageIDs = append(messageIDs, messageID)
		}
	}
	stored, err := s.loadRoomEventsByID(ctx, roomID, messageIDs)
	if err != nil {
		return nil, err
	}
	// A deleted message keeps its bookmark but isn't counted or listed.
	deleted := make(map[string]bool)
	for _, evt := range stored {
		if evt.RedactedBy != "" {
			deleted[string(evt.ID)] = true
		}
	}
	messageIDs = slices.DeleteFunc(messageIDs, func(messageID string) bool { return deleted[messageID] })
	output.MessageIDs = append(output.MessageIDs, messageIDs...)
	if !req.IncludeMessages {
		return output, nil
	}
	events := s.fetchMissingEvents(ctx, roomID, messageIDs, stored)
	messages, err := s.mapEvents(ctx, roomID, events)
	if err != nil {
		return nil, err
	}
	byID := make(map[string]wire.Message, len(messages))
	for _, message := range messages {
		byID[message.ID] = message
	}
	output.Items = make([]wire.Message, 0, len(messageIDs))
	for _, messageID := range messageIDs {
		if message, ok := byID[messageID]; ok && !message.IsDeleted {
			output.Items = append(output.Items, message)
		}
	}
	return output, nil
}

// fetchMissingEvents adds the messages the device never stored to stored,
// fetching a bounded number from the server.
func (s *Dispatcher) fetchMissingEvents(ctx context.Context, roomID id.RoomID, messageIDs []string, stored []*database.Event) []*database.Event {
	have := make(map[id.EventID]bool, len(stored))
	for _, evt := range stored {
		have[evt.ID] = true
	}
	cli := s.rt.Client()
	events := slices.Clone(stored)
	fetched := 0
	for _, messageID := range messageIDs {
		if have[id.EventID(messageID)] || fetched == bookmarkFetchLimit {
			continue
		}
		fetched++
		// A message deleted on the server, or one the account can no longer
		// read, leaves only its bookmark.
		if evt, err := cli.GetEvent(ctx, roomID, id.EventID(messageID)); err == nil && evt != nil {
			events = append(events, evt)
		}
	}
	return events
}
