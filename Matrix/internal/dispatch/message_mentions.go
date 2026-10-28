package dispatch

import (
	"context"
	"net/url"
	"strings"

	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/format"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

func messageMentions(mentions *event.Mentions) *wire.MessageMentions {
	if mentions == nil {
		return nil
	}
	result := &wire.MessageMentions{UserIDs: []string{}, Room: mentions.Room}
	for _, userID := range mentions.UserIDs {
		if userID != "" {
			result.UserIDs = append(result.UserIDs, string(userID))
		}
	}
	return result
}

// Convert only messages containing user links. The SDK handles Matrix HTML,
// entities and whitespace; keeping links avoids guessing ranges from names.
// Both history and realtime call this with the decrypted, latest edited content.
func messageMentionText(content event.MessageEventContent) string {
	if content.Format != event.FormatHTML || content.FormattedBody == "" {
		return ""
	}
	parser := *format.MarkdownHTMLParser
	parser.PillConverter = nil
	hasMention := false
	parser.LinkConverter = func(text, href string, ctx format.Context) string {
		parsed, err := url.Parse(href)
		if err != nil {
			return text
		}
		parsed.Scheme = strings.ToLower(parsed.Scheme)
		// Validate the host before using the SDK's Matrix URI parser.
		if parsed.Scheme == "matrix" || ((parsed.Scheme == "https" || parsed.Scheme == "http") && strings.EqualFold(parsed.Hostname(), "matrix.to")) {
			matrixURI, err := id.ParseMatrixURIOrMatrixToURL(href)
			if err == nil && matrixURI.UserID() != "" && matrixURI.EventID() == "" {
				hasMention = true
				// Canonicalize both matrix: and matrix.to links for the Swift UI.
				href = matrixURI.MatrixToURL()
			}
		}
		switch parsed.Scheme {
		case "http", "https", "mailto", "tel", "matrix":
			return "[" + text + "](<" + strings.ReplaceAll(href, ">", "%3E") + ">)"
		default:
			return text
		}
	}
	parser.TextConverter = func(text string, ctx format.Context) string {
		if ctx.TagStack.Has("code") || ctx.TagStack.Has("pre") {
			return text
		}
		// HTML text is literal, not authored Markdown. In particular, labels
		// containing brackets or underscores must survive conversion unchanged.
		return mentionMarkdownEscapes.Replace(text)
	}
	text := parser.Parse(content.FormattedBody, format.NewContext(context.Background()))
	if !hasMention {
		return ""
	}
	return text
}

var mentionMarkdownEscapes = strings.NewReplacer(
	"\\", "\\\\", "[", "\\[", "]", "\\]", "*", "\\*", "_", "\\_",
	"`", "\\`", "<", "\\<", ">", "\\>", "!", "\\!",
)
