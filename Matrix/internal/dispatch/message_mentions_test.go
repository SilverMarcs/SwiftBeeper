package dispatch

import (
	"encoding/json"
	"testing"

	"go.mau.fi/gomuks/pkg/hicli/database"
	"maunium.net/go/mautrix/event"

	"relay/core/internal/wire"
)

func TestRoomMention(t *testing.T) {
	tests := []struct {
		name     string
		content  string
		isSender bool
		want     bool
	}{
		{"room mention", `{"msgtype":"m.text","body":"@room lunch","m.mentions":{"room":true}}`, false, true},
		{"own room mention", `{"msgtype":"m.text","body":"@room lunch","m.mentions":{"room":true}}`, true, false},
		{"@room text without the flag", `{"msgtype":"m.text","body":"@room lunch","m.mentions":{}}`, false, false},
		{"no mentions", `{"msgtype":"m.text","body":"@room lunch"}`, false, false},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			message := wire.Message{IsSender: test.isSender}
			evt := &database.Event{Content: json.RawMessage(test.content)}
			if err := applyStoredMessageContent(&message, evt, event.EventMessage.Type, "@me:example.org"); err != nil {
				t.Fatal(err)
			}
			if message.IsRoomMention != test.want {
				t.Errorf("IsRoomMention = %v, want %v", message.IsRoomMention, test.want)
			}
		})
	}
}
