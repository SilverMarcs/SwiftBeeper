package dispatch

import (
	"context"
	"net/url"
	"regexp"
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

// messageMarkdownText converts an HTML body to the display Markdown the app
// renders: links keep their labels, lists, headings, quotes and code blocks
// keep their structure, and Matrix user links become matrix.to mentions. The
// SDK handles Matrix HTML, entities and whitespace; keeping links avoids
// guessing ranges from names. It returns "" for a message without HTML, or
// one whose Markdown reads the same as its plain body.
// Both history and realtime call this with the decrypted, latest edited content.
func messageMarkdownText(content event.MessageEventContent) string {
	if content.Format != event.FormatHTML || content.FormattedBody == "" {
		return ""
	}
	parser := *format.MarkdownHTMLParser
	parser.PillConverter = nil
	// Inline HTML would show as literal tags.
	parser.UnderlineConverter = func(text string, ctx format.Context) string { return text }
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
	// Adjacent blocks each add their own line breaks.
	text = extraBlankLines.ReplaceAllString(text, "\n\n")
	if text == content.Body {
		return ""
	}
	return text
}

var extraBlankLines = regexp.MustCompile(`\n{3,}`)

var mentionMarkdownEscapes = strings.NewReplacer(
	"\\", "\\\\", "[", "\\[", "]", "\\]", "*", "\\*", "_", "\\_",
	"`", "\\`", "<", "\\<", ">", "\\>", "!", "\\!", "#", "\\#",
)
