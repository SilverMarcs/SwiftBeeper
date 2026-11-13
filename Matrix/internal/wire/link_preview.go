package wire

// LinkPreview is the card shown under a message for one of its links, from
// the message's bridge or the homeserver's preview of the page.
type LinkPreview struct {
	// URL is what the card opens: the link as it appears in the message.
	URL string `json:"url"`
	// Domain is the URL's host without a leading "www.".
	Domain      string `json:"domain"`
	Title       string `json:"title,omitempty"`
	Description string `json:"description,omitempty"`
	// ImageURL is mxc:// media, served through the local media cache like
	// attachments; encrypted bridge images are decrypted there.
	ImageURL    string `json:"imageURL,omitempty"`
	ImageWidth  int    `json:"imageWidth,omitempty"`
	ImageHeight int    `json:"imageHeight,omitempty"`
}

// LinkPreviewOutput answers get-link-preview. Preview is nil when the page
// has nothing worth a card or the homeserver couldn't preview it.
type LinkPreviewOutput struct {
	Preview *LinkPreview `json:"preview"`
}
