package dispatch

import (
	"context"
	"encoding/json"
	"html"
	"net/url"
	"regexp"
	"strings"

	"maunium.net/go/mautrix"
	"maunium.net/go/mautrix/event"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

var (
	// plainLinkPattern finds web links in plain text, as typed.
	plainLinkPattern = regexp.MustCompile(`(?i)https?://[^\s<>"]+`)
	// htmlLinkPattern finds link targets in an HTML body, for links whose
	// plain text shows only their label.
	htmlLinkPattern = regexp.MustCompile(`(?i)href\s*=\s*"(https?://[^"]+)"`)
)

const (
	// Longer links are tracking soup more often than pages worth a card.
	maxPreviewURLLength = 2048
	// Cards show a few lines; bridges sometimes send whole articles.
	maxPreviewDescriptionLength = 600
)

// applyLinkPreview sets the message's first usable bridge preview or, when
// there is none, the link the app may fetch a preview for once the message
// is on screen. Mapping never fetches anything itself.
func applyLinkPreview(message *wire.Message, content *event.MessageEventContent) {
	if message.Text == "" || message.IsNotice || message.IsDeleted {
		return
	}
	if preview := bridgeLinkPreview(content.BeeperLinkPreviews); preview != nil {
		message.LinkPreview = preview
		return
	}
	message.LinkPreviewURL = previewableLinkURL(message.Text, content)
}

// bridgeLinkPreview maps the first of a bridge's com.beeper.linkpreviews
// with an image or a description. Bridges also send empty entries and
// title-only ones, which aren't worth a card; Slack always sends none.
func bridgeLinkPreview(previews []*event.BeeperLinkPreview) *wire.LinkPreview {
	for _, preview := range previews {
		if preview == nil {
			continue
		}
		link := cleanPreviewURL(preview.MatchedURL)
		if link == "" {
			link = cleanPreviewURL(preview.CanonicalURL)
		}
		if link == "" {
			continue
		}
		image := preview.ImageURL
		if preview.ImageEncryption != nil {
			// The SDK records each encrypted preview image in its media table
			// during sync, so the local media cache decrypts it like an
			// encrypted attachment.
			image = preview.ImageEncryption.URL
		}
		if mapped := newLinkPreview(link, preview.LinkPreview, image); mapped.ImageURL != "" || mapped.Description != "" {
			return mapped
		}
	}
	return nil
}

// homeserverLinkPreview maps the homeserver's preview of link. A title alone
// is enough here: plenty of pages have nothing more than their <title>.
func homeserverLinkPreview(link string, preview *mautrix.RespPreviewURL) *wire.LinkPreview {
	if preview == nil {
		return nil
	}
	mapped := newLinkPreview(link, *preview, preview.ImageURL)
	if mapped.ImageURL == "" && mapped.Description == "" && mapped.Title == "" {
		return nil
	}
	return mapped
}

// newLinkPreview maps OpenGraph data, dropping text that only repeats the
// link or the title and images that aren't Matrix media.
func newLinkPreview(link string, preview event.LinkPreview, image id.ContentURIString) *wire.LinkPreview {
	mapped := &wire.LinkPreview{
		URL:         link,
		Title:       strings.TrimSpace(preview.Title),
		Description: truncateRunes(strings.TrimSpace(preview.Description), maxPreviewDescriptionLength),
	}
	if parsed, err := url.Parse(link); err == nil {
		mapped.Domain = strings.TrimPrefix(strings.ToLower(parsed.Hostname()), "www.")
	}
	if mapped.Title == link || strings.EqualFold(mapped.Title, mapped.Domain) {
		mapped.Title = ""
	}
	if mapped.Description == mapped.Title || mapped.Description == link {
		mapped.Description = ""
	}
	if image.ParseOrIgnore().IsValid() {
		mapped.ImageURL = string(image)
		if preview.ImageWidth > 0 && preview.ImageHeight > 0 {
			mapped.ImageWidth = int(preview.ImageWidth)
			mapped.ImageHeight = int(preview.ImageHeight)
		}
	}
	return mapped
}

// previewableLinkURL is the first link in the text worth previewing, or in
// the HTML body when the text shows none, such as a labeled Slack link.
func previewableLinkURL(text string, content *event.MessageEventContent) string {
	if strings.Contains(text, "://") {
		for _, match := range plainLinkPattern.FindAllString(text, -1) {
			if link := cleanPreviewURL(match); link != "" {
				return link
			}
		}
	}
	if content.Format != event.FormatHTML || !strings.Contains(content.FormattedBody, "://") {
		return ""
	}
	for _, match := range htmlLinkPattern.FindAllStringSubmatch(content.FormattedBody, -1) {
		if link := cleanPreviewURL(html.UnescapeString(match[1])); link != "" {
			return link
		}
	}
	return ""
}

// cleanPreviewURL returns the http(s) link with sentence punctuation trimmed
// from its end, or "" for links without a preview: Matrix mentions and
// permalinks (matrix.to), Matrix API and media URLs, and malformed links.
func cleanPreviewURL(raw string) string {
	link := strings.TrimSpace(raw)
	for link != "" {
		last := link[len(link)-1]
		// A closing parenthesis belongs to the link when it closes one the
		// link opened, as in Wikipedia's "Title_(disambiguation)".
		if last == ')' && strings.Count(link, "(") >= strings.Count(link, ")") {
			break
		}
		if !strings.ContainsRune(".,;:!?)]}'*_~", rune(last)) {
			break
		}
		link = link[:len(link)-1]
	}
	if link == "" || len(link) > maxPreviewURLLength {
		return ""
	}
	parsed, err := url.Parse(link)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Hostname() == "" {
		return ""
	}
	host := strings.ToLower(parsed.Hostname())
	if host == "matrix.to" || strings.HasSuffix(host, ".matrix.to") || strings.Contains(parsed.Path, "/_matrix/") {
		return ""
	}
	return link
}

func truncateRunes(text string, limit int) string {
	runes := []rune(text)
	if len(runes) <= limit {
		return text
	}
	return strings.TrimSpace(string(runes[:limit])) + "…"
}

// getLinkPreview answers the homeserver's preview of a link the app shows,
// fetched once and cached; see linkPreviewCache.
func (s *Dispatcher) getLinkPreview(ctx context.Context, input json.RawMessage) (any, error) {
	var req struct {
		URL string `json:"url"`
	}
	if err := decodeJSON(input, &req); err != nil {
		return nil, err
	}
	link := cleanPreviewURL(req.URL)
	if link == "" {
		return wire.LinkPreviewOutput{}, nil
	}
	preview, err := s.linkPreviews.get(ctx, link, func(ctx context.Context, link string) (*wire.LinkPreview, error) {
		resp, err := s.rt.Client().Client.GetURLPreview(ctx, link)
		if err != nil {
			return nil, err
		}
		return homeserverLinkPreview(link, resp), nil
	})
	if err != nil {
		return nil, err
	}
	return wire.LinkPreviewOutput{Preview: preview}, nil
}
