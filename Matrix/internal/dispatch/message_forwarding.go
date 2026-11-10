package dispatch

import (
	"regexp"
	"strings"

	"maunium.net/go/mautrix/event"
)

// Bridges mark a forwarded message by prefixing its body with a notice
// ("↷ Forwarded"), tagged in HTML with data-mx-forwarded-notice. Relay shows
// a label instead, so a forwarded photo carries no caption of its own and
// can join a gallery.
var forwardedNoticeHTML = regexp.MustCompile(`(?is)^\s*<p[^>]*\bdata-mx-forwarded-notice\b[^>]*>.*?</p>`)

const forwardedNoticeText = "↷ Forwarded"

// removeForwardedNotice strips the notice from content, reporting whether
// it did. A text message that is nothing but the notice keeps it, since it
// would otherwise look empty.
func removeForwardedNotice(content *event.MessageEventContent) bool {
	if content.Format != event.FormatHTML || !forwardedNoticeHTML.MatchString(content.FormattedBody) {
		return false
	}
	body, ok := strings.CutPrefix(strings.TrimLeft(content.Body, " \n"), forwardedNoticeText)
	if !ok {
		return false
	}
	body = strings.TrimLeft(body, "\n")
	isMedia := content.MsgType == event.MsgImage || content.MsgType == event.MsgVideo ||
		content.MsgType == event.MsgAudio || content.MsgType == event.MsgFile
	if body == "" && !isMedia {
		return false
	}
	if body == "" {
		// The media's filename stands in for an absent caption.
		body = content.GetFileName()
	}
	content.Body = body
	content.FormattedBody = forwardedNoticeHTML.ReplaceAllString(content.FormattedBody, "")
	if strings.TrimSpace(content.FormattedBody) == "" {
		content.Format = ""
		content.FormattedBody = ""
	}
	return true
}
