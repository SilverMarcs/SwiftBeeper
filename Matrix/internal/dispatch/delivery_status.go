package dispatch

import (
	"cmp"
	"context"
	"encoding/json"
	"fmt"
	"slices"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

// Beeper bridges report each outgoing message's fate in a
// com.beeper.message_send_status event that references it: SUCCESS once the
// network took it, again with delivered_to_users when the recipient's device
// confirms it (direct chats on networks with delivery receipts, such as
// WhatsApp and Messenger), or a failure. A retried send reports again, so the
// newest report wins, except that a delivery, once confirmed, stays.
const messageStatusEventsQuery = `
	SELECT rowid, -1,
	       room_id, event_id, sender, type, state_key, timestamp, content, decrypted, decrypted_type,
	       unsigned, local_content, transaction_id, redacted_by, relates_to, relation_type,
	       megolm_session_id, decryption_error, send_error, reactions, last_edit_rowid, unread_type
	FROM event
	WHERE room_id = ? AND relation_type = 'm.reference' AND relates_to IN (%s)
	  AND (type = ? OR decrypted_type = ?)`

// applyDeliveryStatuses sets each outgoing message's delivery status from the
// bridge's reports. Messages still render when the reports can't be read.
func (s *Dispatcher) applyDeliveryStatuses(ctx context.Context, roomID id.RoomID, messages []wire.Message) {
	params := []any{roomID}
	for _, message := range messages {
		if message.IsSender {
			params = append(params, message.ID)
		}
	}
	if len(params) == 1 {
		return
	}
	slots := len(params) - 1
	params = append(params, event.BeeperMessageStatus.Type, event.BeeperMessageStatus.Type)
	events, err := s.rt.Client().DB.Event.QueryMany(ctx, fmt.Sprintf(messageStatusEventsQuery, sqlSlots(slots)), params...)
	if err != nil || len(events) == 0 {
		return
	}
	// Sorted here rather than in SQL, where ordering by rowid makes SQLite
	// scan the whole room instead of using the relation index.
	slices.SortFunc(events, func(a, b *database.Event) int { return cmp.Compare(a.RowID, b.RowID) })
	reports := make(map[id.EventID]*deliveryReport)
	for _, evt := range events {
		var content event.BeeperMessageStatusEventContent
		if json.Unmarshal(evt.GetContent(), &content) != nil {
			continue
		}
		report := reports[evt.RelatesTo]
		if report == nil {
			report = &deliveryReport{}
			reports[evt.RelatesTo] = report
		}
		report.apply(content)
	}
	for index := range messages {
		if report := reports[id.EventID(messages[index].ID)]; report != nil {
			messages[index].DeliveryStatus, messages[index].DeliveryError = report.result()
		}
	}
}

// deliveryReport folds one message's status events, oldest first.
type deliveryReport struct {
	status    wire.DeliveryStatus
	err       string
	delivered bool
}

func (r *deliveryReport) apply(content event.BeeperMessageStatusEventContent) {
	switch content.Status {
	case event.MessageStatusSuccess:
		r.status, r.err = wire.DeliveryStatusSent, ""
		if content.DeliveredToUsers != nil && len(*content.DeliveredToUsers) > 0 {
			r.delivered = true
		}
	case event.MessageStatusRetriable, event.MessageStatusFail:
		// The message is the bridge's user-facing explanation.
		r.status, r.err = wire.DeliveryStatusFailed, content.Message
	}
}

func (r *deliveryReport) result() (wire.DeliveryStatus, string) {
	if r.status == wire.DeliveryStatusSent && r.delivered {
		return wire.DeliveryStatusDelivered, ""
	}
	return r.status, r.err
}
