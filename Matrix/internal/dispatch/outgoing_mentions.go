package dispatch

import (
	"errors"
	"slices"
	"strings"
	"unicode/utf16"

	"maunium.net/go/mautrix/format"
	"maunium.net/go/mautrix/id"

	"relay/core/internal/wire"
)

// Insert SDK-generated Matrix links only at explicitly selected spans. Keep
// UTF-16 wire offsets separate from UTF-8 byte offsets, including for emoji.
func outgoingMentionText(text string, mentions []wire.ComposerMention) (string, error) {
	if len(mentions) == 0 {
		return strings.TrimSpace(text), nil
	}
	boundaries := map[int]int{0: 0}
	units := 0
	for offset, char := range text {
		boundaries[units] = offset
		units += utf16.RuneLen(char)
	}
	boundaries[units] = len(text)
	mentions = slices.Clone(mentions)
	slices.SortFunc(mentions, func(a, b wire.ComposerMention) int { return a.Location - b.Location })
	var result strings.Builder
	previous := 0
	for _, mention := range mentions {
		start, startOK := boundaries[mention.Location]
		end, endOK := boundaries[mention.Location+mention.Length]
		userID := id.UserID(mention.UserID)
		if _, _, err := userID.Parse(); err != nil {
			return "", errors.New("mentions: invalid user ID")
		}
		if !startOK || !endOK || mention.Length <= 0 || start < previous || end <= start {
			return "", errors.New("mentions: invalid or overlapping text range")
		}
		result.WriteString(text[previous:start])
		result.WriteString(format.MarkdownMentionWithName(text[start:end], userID))
		previous = end
	}
	result.WriteString(text[previous:])
	return strings.TrimSpace(result.String()), nil
}
