package notifications

import (
	"strings"
	"unicode"
	"unicode/utf8"
)

// Notifications show at most a few hundred characters, so plainText reads only
// this much of a long message. Stripping only shortens text.
const plainTextInputLimit = 4000

// plainText removes Markdown syntax from a message body for a notification:
// emphasis, code and strikethrough markers, link and image targets, heading,
// quote and rule lines, code fences and table borders. List items keep a
// bullet, and blank lines between paragraphs are dropped so more text fits.
//
// It makes one pass over each line without regular expressions or a document
// tree, and leaves anything that isn't clearly Markdown as written: a marker
// only counts when it has a matching closer on the same line and sits at a word
// boundary, so snake_case, 2*3*4 and "~5 min" are unchanged.
func plainText(body string) string {
	if !strings.ContainsAny(body, "*_~`[]<>#|\\-+=") {
		return body
	}
	source, truncated := body, false
	if len(source) > plainTextInputLimit {
		cut := plainTextInputLimit
		for cut > 0 && !utf8.RuneStart(source[cut]) {
			cut--
		}
		source, truncated = source[:cut], true
	}
	var out strings.Builder
	out.Grow(len(source))
	inCode := false
	for line := range strings.Lines(source) {
		line = strings.TrimRight(line, " \t\r\n")
		trimmed := strings.TrimLeft(line, " \t")
		if isFence(trimmed) {
			inCode = !inCode
			continue
		}
		if inCode {
			// Code keeps its text as written, without the indentation.
			if trimmed != "" {
				writeLine(&out, trimmed)
			}
			continue
		}
		var text strings.Builder
		if plainLine(trimmed, &text) {
			writeLine(&out, text.String())
		}
	}
	result := out.String()
	if strings.TrimSpace(result) == "" {
		// Nothing but syntax, such as a lone rule: show what was sent.
		return strings.TrimSpace(body)
	}
	if truncated {
		result += "…"
	}
	return result
}

func writeLine(out *strings.Builder, line string) {
	if out.Len() > 0 {
		out.WriteByte('\n')
	}
	out.WriteString(line)
}

// isFence reports whether a line opens or closes a code block. A line that
// also closes its own fence, like ```code```, is inline code instead.
func isFence(line string) bool {
	for _, fence := range []string{"```", "~~~"} {
		if strings.HasPrefix(line, fence) {
			return !strings.Contains(strings.TrimLeft(line, fence[:1]), fence)
		}
	}
	return false
}

// plainLine writes one line's text without its block syntax, and reports
// false for a line that is only syntax, such as a blank line or a rule.
func plainLine(line string, out *strings.Builder) bool {
	// Quotes, which can nest and hold any other block.
	for strings.HasPrefix(line, ">") {
		line = strings.TrimLeft(line[1:], " \t")
	}
	if line == "" || isRule(line) || isTableSeparator(line) {
		return false
	}
	if heading := headingText(line); heading != line {
		if heading == "" {
			return false
		}
		plainInline(heading, out)
		return true
	}
	if marker, rest, ok := listItem(line); ok {
		out.WriteString(marker)
		plainInline(rest, out)
		return true
	}
	if strings.HasPrefix(line, "|") {
		// A table row: its cells, separated like a list of values.
		cells := strings.Split(strings.Trim(line, "|"), "|")
		written := false
		for _, cell := range cells {
			if cell = strings.TrimSpace(cell); cell == "" {
				continue
			}
			if written {
				out.WriteString(" · ")
			}
			plainInline(cell, out)
			written = true
		}
		return written
	}
	plainInline(line, out)
	return true
}

// isRule reports a thematic break (---, ***, ___) or a setext heading
// underline (===), which carry no text.
func isRule(line string) bool {
	marker := line[0]
	if marker != '-' && marker != '*' && marker != '_' && marker != '=' {
		return false
	}
	count := 0
	for i := range len(line) {
		switch line[i] {
		case marker:
			count++
		case ' ', '\t':
		default:
			return false
		}
	}
	return count >= 3
}

// isTableSeparator reports a table's header separator, like |---|:--:|.
func isTableSeparator(line string) bool {
	if !strings.Contains(line, "|") || !strings.Contains(line, "-") {
		return false
	}
	for i := range len(line) {
		switch line[i] {
		case '|', '-', ':', ' ', '\t':
		default:
			return false
		}
	}
	return true
}

// headingText returns an ATX heading's text, or the line unchanged when it
// isn't one. "#hashtag" isn't a heading.
func headingText(line string) string {
	level := 0
	for level < len(line) && line[level] == '#' {
		level++
	}
	if level == 0 || level > 6 || (level < len(line) && line[level] != ' ' && line[level] != '\t') {
		return line
	}
	text := strings.TrimSpace(line[level:])
	// An optional closing sequence: "## Title ##".
	if closing := strings.TrimRight(text, "#"); closing != text && (closing == "" || strings.HasSuffix(closing, " ")) {
		text = strings.TrimSpace(closing)
	}
	return text
}

// listItem splits a list item into the marker to show and its text. Bullets
// become •, task items ☐ or ☑, and numbered items keep their number.
func listItem(line string) (marker, rest string, ok bool) {
	if len(line) >= 2 && (line[0] == '-' || line[0] == '*' || line[0] == '+') && (line[1] == ' ' || line[1] == '\t') {
		rest = strings.TrimLeft(line[2:], " \t")
		switch {
		case strings.HasPrefix(rest, "[ ] "):
			return "☐ ", rest[4:], true
		case strings.HasPrefix(rest, "[x] "), strings.HasPrefix(rest, "[X] "):
			return "☑ ", rest[4:], true
		}
		return "• ", rest, true
	}
	digits := 0
	for digits < len(line) && digits < 9 && line[digits] >= '0' && line[digits] <= '9' {
		digits++
	}
	if digits > 0 && digits+1 < len(line) && (line[digits] == '.' || line[digits] == ')') &&
		(line[digits+1] == ' ' || line[digits+1] == '\t') {
		return line[:digits] + ". ", strings.TrimLeft(line[digits+2:], " \t"), true
	}
	return "", "", false
}

// plainInline writes text without inline Markdown: emphasis, strikethrough and
// code markers, link and image targets, autolink brackets and escapes.
func plainInline(s string, out *strings.Builder) {
	for i := 0; i < len(s); {
		c := s[i]
		switch c {
		case '\\':
			if i+1 < len(s) && isASCIIPunctuation(s[i+1]) {
				out.WriteByte(s[i+1])
				i += 2
				continue
			}
		case '`':
			n := runLength(s, i)
			if end := closingRun(s, i+n, c, n, false); end >= 0 {
				// Code is literal: nothing inside it is Markdown.
				out.WriteString(strings.TrimSpace(s[i+n : end]))
				i = end + n
				continue
			}
			out.WriteString(s[i : i+n])
			i += n
			continue
		case '!':
			if i+1 < len(s) && s[i+1] == '[' {
				if label, next, ok := link(s, i+1); ok {
					if strings.TrimSpace(label) == "" {
						label = "Image"
					}
					plainInline(label, out)
					i = next
					continue
				}
			}
		case '[':
			if label, next, ok := link(s, i); ok {
				plainInline(label, out)
				i = next
				continue
			}
		case '<':
			// An autolink, <https://example.com>, shows its address.
			if end := strings.IndexByte(s[i+1:], '>'); end > 0 {
				address := s[i+1 : i+1+end]
				if !strings.ContainsAny(address, " \t<") && (strings.Contains(address, "://") || strings.HasPrefix(address, "mailto:")) {
					out.WriteString(strings.TrimPrefix(address, "mailto:"))
					i += end + 2
					continue
				}
			}
		case 'h':
			// A bare address is literal, so underscores in it stay.
			if (strings.HasPrefix(s[i:], "https://") || strings.HasPrefix(s[i:], "http://")) && !isWordBefore(s, i) {
				end := strings.IndexAny(s[i:], " \t")
				if end < 0 {
					end = len(s) - i
				}
				out.WriteString(s[i : i+end])
				i += end
				continue
			}
		case '*', '_', '~':
			n := runLength(s, i)
			if n <= 3 && opensEmphasis(s, i, n) {
				if end := closingRun(s, i+n, c, n, true); end >= 0 {
					plainInline(s[i+n:end], out)
					i = end + n
					continue
				}
			}
			out.WriteString(s[i : i+n])
			i += n
			continue
		}
		out.WriteByte(c)
		i++
	}
}

// runLength counts the repeats of the byte at i.
func runLength(s string, i int) int {
	n := 1
	for i+n < len(s) && s[i+n] == s[i] {
		n++
	}
	return n
}

// opensEmphasis reports a marker run that starts a word: not after a letter
// or digit, and followed by text rather than a space.
func opensEmphasis(s string, i, n int) bool {
	return i+n < len(s) && !isSpace(s[i+n]) && !isWordBefore(s, i)
}

// closingRun finds a run of exactly n markers from start, returning its index
// or -1. An emphasis closer ends a word: after text, not before a letter or
// digit.
func closingRun(s string, start int, marker byte, n int, emphasis bool) int {
	for j := start; j < len(s); {
		if s[j] == '\\' && emphasis {
			// An escaped marker can't close; backslashes in code are literal.
			j += 2
			continue
		}
		if s[j] != marker {
			j++
			continue
		}
		length := runLength(s, j)
		if length == n && (!emphasis || (j > start && !isSpace(s[j-1]) && !isWordAt(s, j+n))) {
			return j
		}
		j += length
	}
	return -1
}

// link parses [label](target), [label](<target>) or [label][reference] at
// s[i] == '[', returning the label and the index after the link.
func link(s string, i int) (label string, next int, ok bool) {
	depth := 0
	closeLabel := -1
	for j := i; j < len(s) && closeLabel < 0; j++ {
		switch s[j] {
		case '\\':
			j++
		case '[':
			depth++
		case ']':
			depth--
			if depth == 0 {
				closeLabel = j
			}
		}
	}
	if closeLabel < 0 || closeLabel+1 >= len(s) {
		return "", 0, false
	}
	label = s[i+1 : closeLabel]
	switch s[closeLabel+1] {
	case '(':
		depth = 0
		for j := closeLabel + 1; j < len(s); j++ {
			switch s[j] {
			case '\\':
				j++
			case '(':
				depth++
			case ')':
				depth--
				if depth == 0 {
					return label, j + 1, true
				}
			case '<':
				// A bracketed target can hold unbalanced parentheses.
				if end := strings.IndexByte(s[j:], '>'); end > 0 {
					j += end
				}
			}
		}
	case '[':
		if end := strings.IndexByte(s[closeLabel+2:], ']'); end >= 0 && !strings.ContainsAny(s[closeLabel+2:closeLabel+2+end], "[ ") {
			return label, closeLabel + 3 + end, true
		}
	}
	return "", 0, false
}

func isSpace(c byte) bool { return c == ' ' || c == '\t' }

// isWordBefore reports a letter or digit just before s[i].
func isWordBefore(s string, i int) bool {
	r, _ := utf8.DecodeLastRuneInString(s[:i])
	return r != utf8.RuneError && (unicode.IsLetter(r) || unicode.IsDigit(r))
}

// isWordAt reports a letter or digit at s[i].
func isWordAt(s string, i int) bool {
	r, _ := utf8.DecodeRuneInString(s[i:])
	return r != utf8.RuneError && (unicode.IsLetter(r) || unicode.IsDigit(r))
}

func isASCIIPunctuation(c byte) bool {
	return (c >= '!' && c <= '/') || (c >= ':' && c <= '@') || (c >= '[' && c <= '`') || (c >= '{' && c <= '~')
}
