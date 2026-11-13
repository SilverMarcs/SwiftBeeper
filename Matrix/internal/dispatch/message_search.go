package dispatch

import (
	"context"
	"encoding/json"
	"fmt"
	"slices"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"golang.org/x/text/runes"
	"golang.org/x/text/transform"
	"golang.org/x/text/unicode/norm"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

const messageSearchPageSize = 30

// searchMessages finds messages in every chat containing each word of the
// query, a word matching as a prefix, newest first. It reads the local index
// only; history never fetched isn't found.
func (s *Dispatcher) searchMessages(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		Query      string   `json:"query"`
		AccountIDs []string `json:"accountIDs"`
		Cursor     string   `json:"cursor"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	output := wire.SearchMessagesOutput{Items: []wire.Message{}, Chats: []wire.Chat{}}
	match, words := messageSearchMatch(req.Query)
	if match == "" {
		return output, nil
	}
	var before int64
	hasCursor := req.Cursor != ""
	if hasCursor {
		var err error
		if before, err = strconv.ParseInt(req.Cursor, 10, 64); err != nil {
			return nil, fmt.Errorf("invalid cursor: %w", err)
		}
	}
	if err := s.ensureMessageSearchIndex(ctx); err != nil {
		return nil, err
	}

	// The index holds tokens only, so this reads no message text; rowid
	// order is close to arrival order, newest first.
	cli := s.rt.Client()
	rows, err := cli.DB.Query(ctx, `SELECT rowid FROM relay_message_search WHERE relay_message_search MATCH ?
		AND (?=0 OR rowid<?) ORDER BY rowid DESC LIMIT ?`, match, hasCursor, before, messageSearchPageSize+1)
	if err != nil {
		return nil, fmt.Errorf("failed to search messages: %w", err)
	}
	var hits []database.EventRowID
	for rows.Next() {
		var rowID database.EventRowID
		if err = rows.Scan(&rowID); err != nil {
			rows.Close()
			return nil, err
		}
		hits = append(hits, rowID)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return nil, err
	}
	if output.HasMore = len(hits) > messageSearchPageSize; output.HasMore {
		hits = hits[:messageSearchPageSize]
	}
	if len(hits) == 0 {
		return output, nil
	}
	output.Cursor = strconv.FormatInt(int64(hits[len(hits)-1]), 10)

	messages, err := s.loadSearchHits(ctx, hits)
	if err != nil {
		return nil, err
	}
	chats, err := s.loadSearchChats(ctx, messages, req.AccountIDs)
	if err != nil {
		return nil, err
	}
	names := s.loadNamesForEvents(ctx, messages)
	for _, evt := range messages {
		if _, ok := chats[evt.RoomID]; !ok {
			continue
		}
		message, err := s.mapEventToMessage(evt, names[evt.RoomID], nil)
		// The index also matched reply fallbacks quoting another message, and
		// text an edit has since replaced.
		if err != nil || !messageMatchesWords(message, words) {
			continue
		}
		output.Items = append(output.Items, message)
	}
	for _, message := range output.Items {
		if chat, ok := chats[id.RoomID(message.ChatID)]; ok {
			output.Chats = append(output.Chats, chat)
			delete(chats, id.RoomID(message.ChatID))
		}
	}
	return output, nil
}

// loadSearchHits loads the matched events, newest first, resolving a matched
// edit to the message it edits and dropping duplicates. Each message carries
// its latest edit, which the result shows.
func (s *Dispatcher) loadSearchHits(ctx context.Context, hits []database.EventRowID) ([]*database.Event, error) {
	cli := s.rt.Client()
	events, err := cli.DB.Event.GetByRowIDs(ctx, hits...)
	if err != nil {
		return nil, fmt.Errorf("failed to load search results: %w", err)
	}
	byRowID := make(map[database.EventRowID]*database.Event, len(events))
	for _, evt := range events {
		byRowID[evt.RowID] = evt
	}
	seen := make(map[id.EventID]bool, len(hits))
	messages := make([]*database.Event, 0, len(hits))
	for _, rowID := range hits {
		evt := byRowID[rowID]
		if evt == nil {
			continue
		}
		if evt.RelationType == event.RelReplace {
			if evt, err = cli.DB.Event.GetByID(ctx, evt.RelatesTo); err != nil {
				return nil, err
			}
		}
		if evt == nil || evt.RedactedBy != "" || seen[evt.ID] {
			continue
		}
		seen[evt.ID] = true
		messages = append(messages, evt)
	}
	if err = s.populateLastEditRefs(ctx, messages); err != nil {
		return nil, err
	}
	if err = s.populateTimelinePositions(ctx, messages); err != nil {
		return nil, err
	}
	// Timeline order within the page, as the index's order is only close.
	slices.SortStableFunc(messages, func(a, b *database.Event) int {
		return b.Timestamp.Compare(a.Timestamp.Time)
	})
	return messages, nil
}

// loadSearchChats maps the chats the results are in, on the requested
// accounts, without previews or read state, which result rows don't show.
func (s *Dispatcher) loadSearchChats(ctx context.Context, messages []*database.Event, accountIDs []string) (map[id.RoomID]wire.Chat, error) {
	var rooms []*database.Room
	seen := make(map[id.RoomID]bool)
	cli := s.rt.Client()
	for _, evt := range messages {
		if seen[evt.RoomID] {
			continue
		}
		seen[evt.RoomID] = true
		room, err := cli.DB.Room.Get(ctx, evt.RoomID)
		if err != nil {
			return nil, err
		}
		if room != nil && (room.CreationContent == nil || room.CreationContent.Type != event.RoomTypeSpace) {
			rooms = append(rooms, room)
		}
	}
	chats := make(map[id.RoomID]wire.Chat, len(rooms))
	if len(rooms) == 0 {
		return chats, nil
	}
	lookup, err := s.buildAccountLookup(ctx)
	if err != nil {
		return nil, err
	}
	summaries, err := s.loadChatMemberSummaries(ctx, rooms, chatPreviewParticipants, lookup)
	if err != nil {
		return nil, err
	}
	for _, room := range rooms {
		if len(accountIDs) > 0 && !slices.Contains(accountIDs, lookup.roomAccounts[room.ID]) {
			continue
		}
		chats[room.ID] = s.mapRoomToChat(room, summaries[room.ID], lookup, roomAccountDataState{}, "")
	}
	return chats, nil
}

// messageSearchMatch turns a query into an FTS5 expression requiring every
// word, each as a quoted phrase so punctuation can't form operators. Words
// of two or more characters match as prefixes, for results while typing.
// It also returns the folded words for checking results.
func messageSearchMatch(query string) (string, []string) {
	var terms, words []string
	for _, word := range strings.Fields(query) {
		if !strings.ContainsFunc(word, func(r rune) bool { return unicode.IsLetter(r) || unicode.IsNumber(r) }) {
			continue
		}
		term := `"` + strings.ReplaceAll(word, `"`, `""`) + `"`
		if utf8.RuneCountInString(word) >= 2 {
			term += "*"
		}
		terms = append(terms, term)
		words = append(words, foldForSearch(strings.Trim(word, `"'.,;:!?()[]{}`)))
	}
	return strings.Join(terms, " "), words
}

// messageMatchesWords reports whether the message's text, or its file's
// name, holds every folded word.
func messageMatchesWords(message wire.Message, words []string) bool {
	text := message.Text
	if len(message.Attachments) > 0 {
		text += "\n" + message.Attachments[0].FileName
	}
	text = foldForSearch(text)
	for _, word := range words {
		if !strings.Contains(text, word) {
			return false
		}
	}
	return true
}

// foldForSearch lowercases and strips diacritics, as the index's tokenizer
// does, so "Café" holds "cafe".
func foldForSearch(text string) string {
	folded, _, err := transform.String(transform.Chain(norm.NFD, runes.Remove(runes.In(unicode.Mn)), norm.NFC), text)
	if err != nil {
		folded = text
	}
	return strings.ToLower(folded)
}
