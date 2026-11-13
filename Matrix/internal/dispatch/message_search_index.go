package dispatch

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"log"
	"sync"
)

// The message search index is an FTS5 table beside the SDK's event table,
// holding only tokens (contentless), keyed by event rowid. Triggers on the
// event table keep it current through every path that writes events: sync,
// decryption, edits, redactions and pagination, in any process that opens the
// store. Existing events are indexed once, in small batches, in the
// background.
const (
	// messageSearchIndexVersion rebuilds the index when its schema or the
	// indexed text changes.
	messageSearchIndexVersion = 1
	messageSearchBackfillStep = 2000
)

// searchableEventSQL is true for a row the index holds: a message or edit
// with text, not a notice, not redacted. row is NEW, OLD or event.
func searchableEventSQL(row string) string {
	content := `COALESCE(` + row + `.decrypted,` + row + `.content)`
	return `(COALESCE(` + row + `.decrypted_type,` + row + `.type)='m.room.message' AND ` + row + `.state_key IS NULL
		AND ` + row + `.redacted_by IS NULL AND json_valid(` + content + `)
		AND COALESCE(json_extract(` + content + `,'$.msgtype'),'')<>'m.notice'
		AND ` + searchableBodySQL(row) + ` IS NOT NULL)`
}

// searchableBodySQL is the text indexed for a row: an edit's new body, or
// the message's body, which for media is its caption or file name.
func searchableBodySQL(row string) string {
	content := `COALESCE(` + row + `.decrypted,` + row + `.content)`
	return `(CASE WHEN ` + row + `.relation_type='m.replace'
		THEN json_extract(` + content + `,'$."m.new_content".body')
		ELSE json_extract(` + content + `,'$.body') END)`
}

func messageSearchSchemaSQL() []string {
	return []string{
		`CREATE VIRTUAL TABLE relay_message_search USING fts5(
			body, content='', contentless_delete=1, tokenize='unicode61 remove_diacritics 2')`,
		`CREATE TRIGGER relay_message_search_insert AFTER INSERT ON event
			WHEN ` + searchableEventSQL("NEW") + ` BEGIN
			INSERT OR REPLACE INTO relay_message_search(rowid, body) VALUES (NEW.rowid, ` + searchableBodySQL("NEW") + `);
		END`,
		// Only changes to the indexed inputs touch the index; the SDK rewrites
		// rows for reactions, receipts and edit links far more often.
		`CREATE TRIGGER relay_message_search_update AFTER UPDATE OF content, decrypted, decrypted_type, redacted_by, relation_type ON event
			WHEN OLD.content IS NOT NEW.content OR OLD.decrypted IS NOT NEW.decrypted
				OR OLD.decrypted_type IS NOT NEW.decrypted_type OR OLD.redacted_by IS NOT NEW.redacted_by
				OR OLD.relation_type IS NOT NEW.relation_type BEGIN
			DELETE FROM relay_message_search WHERE rowid=OLD.rowid;
			INSERT INTO relay_message_search(rowid, body) SELECT NEW.rowid, ` + searchableBodySQL("NEW") + `
				WHERE ` + searchableEventSQL("NEW") + `;
		END`,
		`CREATE TRIGGER relay_message_search_delete AFTER DELETE ON event BEGIN
			DELETE FROM relay_message_search WHERE rowid=OLD.rowid;
		END`,
	}
}

var messageSearchDropSQL = []string{
	`DROP TRIGGER IF EXISTS relay_message_search_insert`,
	`DROP TRIGGER IF EXISTS relay_message_search_update`,
	`DROP TRIGGER IF EXISTS relay_message_search_delete`,
	`DROP TABLE IF EXISTS relay_message_search`,
}

// messageSearchIndex prepares the index once per opened store.
type messageSearchIndex struct {
	mu          sync.Mutex
	schemaReady bool
	backfilling bool
	// generation changes each time the store closes, ending a backfill that
	// was running on it.
	generation int
}

// ResetMessageSearch forgets the index state when the store closes, as the
// iOS app's does in the background. The next start re-reads it and resumes
// an unfinished backfill from its recorded progress.
func (s *Dispatcher) ResetMessageSearch() {
	s.searchIndex.mu.Lock()
	defer s.searchIndex.mu.Unlock()
	s.searchIndex.schemaReady = false
	s.searchIndex.backfilling = false
	s.searchIndex.generation++
}

// PrepareMessageSearch creates or upgrades the index and starts indexing
// stored events. The app calls it at launch so the first search finds the
// index ready; searching calls it too, in case that hasn't happened.
func (s *Dispatcher) PrepareMessageSearch(ctx context.Context) {
	if err := s.ensureMessageSearchIndex(ctx); err != nil {
		log.Printf("message search index: %v", err)
	}
}

// ensureMessageSearchIndex makes sure the index exists. Stored events are
// indexed in the background, so searches during that see the newest first.
func (s *Dispatcher) ensureMessageSearchIndex(ctx context.Context) error {
	s.searchIndex.mu.Lock()
	defer s.searchIndex.mu.Unlock()
	if s.searchIndex.schemaReady {
		return nil
	}
	if err := s.requireLoggedInSession(); err != nil {
		return err
	}
	db := s.rt.Client().DB
	if _, err := db.Exec(ctx, `CREATE TABLE IF NOT EXISTS relay_message_search_state (
		version INTEGER NOT NULL, backfill_below INTEGER NOT NULL)`); err != nil {
		return err
	}
	var version, backfillBelow int64
	err := db.QueryRow(ctx, `SELECT version, backfill_below FROM relay_message_search_state`).Scan(&version, &backfillBelow)
	if errors.Is(err, sql.ErrNoRows) {
		version = 0
	} else if err != nil {
		return err
	}
	if version != messageSearchIndexVersion {
		// Triggers cover every row written from here on; rows already stored,
		// below this point, are the backfill's.
		err = db.DoTxn(ctx, nil, func(ctx context.Context) error {
			for _, statement := range append(append([]string{}, messageSearchDropSQL...), messageSearchSchemaSQL()...) {
				if _, err := db.Exec(ctx, statement); err != nil {
					return err
				}
			}
			if err := db.QueryRow(ctx, `SELECT COALESCE(MAX(rowid),0)+1 FROM event`).Scan(&backfillBelow); err != nil {
				return err
			}
			if _, err := db.Exec(ctx, `DELETE FROM relay_message_search_state`); err != nil {
				return err
			}
			_, err := db.Exec(ctx, `INSERT INTO relay_message_search_state (version, backfill_below) VALUES (?, ?)`,
				messageSearchIndexVersion, backfillBelow)
			return err
		})
		if err != nil {
			return fmt.Errorf("failed to create index: %w", err)
		}
	}
	s.searchIndex.schemaReady = true
	if backfillBelow > 1 && !s.searchIndex.backfilling {
		s.searchIndex.backfilling = true
		go s.backfillMessageSearch(backfillBelow, s.searchIndex.generation)
	}
	return nil
}

// backfillMessageSearch indexes events stored before the index existed,
// newest first so recent messages are searchable soonest. Each step is its
// own short write, leaving room for sync between them, and records its
// progress so an interrupted backfill resumes.
func (s *Dispatcher) backfillMessageSearch(below int64, generation int) {
	isCurrent := func() bool {
		s.searchIndex.mu.Lock()
		defer s.searchIndex.mu.Unlock()
		return s.searchIndex.generation == generation
	}
	defer func() {
		s.searchIndex.mu.Lock()
		if s.searchIndex.generation == generation {
			s.searchIndex.backfilling = false
		}
		s.searchIndex.mu.Unlock()
	}()
	ctx := context.Background()
	query := `INSERT OR REPLACE INTO relay_message_search(rowid, body)
		SELECT event.rowid, ` + searchableBodySQL("event") + ` FROM event
		WHERE event.rowid>=? AND event.rowid<? AND ` + searchableEventSQL("event")
	for below > 1 {
		cli := s.rt.Client()
		if cli == nil || !isCurrent() {
			return
		}
		from := max(below-messageSearchBackfillStep, 1)
		err := cli.DB.DoTxn(ctx, nil, func(ctx context.Context) error {
			if _, err := cli.DB.Exec(ctx, query, from, below); err != nil {
				return err
			}
			_, err := cli.DB.Exec(ctx, `UPDATE relay_message_search_state SET backfill_below=?`, from)
			return err
		})
		if err != nil {
			log.Printf("message search index: failed to index stored messages: %v", err)
			return
		}
		below = from
	}
}
