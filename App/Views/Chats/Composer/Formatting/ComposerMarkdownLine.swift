import Foundation

/// One line of a draft, with the Markdown container syntax at its start
/// picked apart: quote markers, indentation and a list marker. Positions are
/// UTF-16 offsets into the whole draft, as `NSRange`s use.
struct ComposerMarkdownLine {
    enum ListMarker: Equatable {
        /// `-`, `*` or `+`.
        case bullet(UInt16)
        /// `1.` or `1)`.
        case ordered(number: Int, delimiter: UInt16)
    }

    /// The line, without its newline.
    let range: NSRange
    /// Where the line's `>` markers, and the space after each, end.
    let quoteEnd: Int
    let quoteDepth: Int
    /// Spaces between the quote markers and the rest of the line.
    let indent: Int
    let marker: ListMarker?
    /// The list marker's own characters, without the space after it.
    let markerRange: NSRange?
    /// Where the line's text starts, after its markers and their spaces.
    let contentStart: Int

    var end: Int { NSMaxRange(range) }
    var contentRange: NSRange { NSRange(location: contentStart, length: end - contentStart) }
    /// The quote markers, indentation and list marker before the text.
    var prefixRange: NSRange { NSRange(location: range.location, length: contentStart - range.location) }

    /// Parses the line in `chars` covering `range`.
    init(chars: [UInt16], range: NSRange) {
        self.range = range
        let end = NSMaxRange(range)
        var position = range.location

        // Each `>` may follow up to three spaces, and takes one space after it.
        var depth = 0
        while true {
            var probe = position
            while probe < end, probe - position < 3, chars[probe] == .space { probe += 1 }
            guard probe < end, chars[probe] == .greaterThan else { break }
            probe += 1
            if probe < end, chars[probe] == .space { probe += 1 }
            position = probe
            depth += 1
        }
        quoteEnd = position
        quoteDepth = depth

        var indent = 0
        while position < end, chars[position] == .space || chars[position] == .tab {
            indent += chars[position] == .tab ? 4 : 1
            position += 1
        }
        self.indent = indent

        let (marker, markerLength) = Self.listMarker(in: chars, at: position, end: end)
        self.marker = marker
        if marker != nil {
            markerRange = NSRange(location: position, length: markerLength)
            position += markerLength
            while position < end, chars[position] == .space { position += 1 }
        } else {
            markerRange = nil
        }
        contentStart = position
    }

    /// A list marker at `position`: followed by a space or the line's end.
    private static func listMarker(in chars: [UInt16], at position: Int, end: Int) -> (ListMarker?, Int) {
        guard position < end else { return (nil, 0) }
        let first = chars[position]
        func endsMarker(_ index: Int) -> Bool { index == end || chars[index] == .space }
        if first == .hyphen || first == .asterisk || first == .plus {
            return endsMarker(position + 1) ? (.bullet(first), 1) : (nil, 0)
        }
        var index = position
        var number = 0
        while index < end, index - position < 9, let digit = chars[index].asciiDigit {
            number = number * 10 + digit
            index += 1
        }
        guard index > position, index < end, chars[index] == .period || chars[index] == .closingParenthesis,
              endsMarker(index + 1) else { return (nil, 0) }
        return (.ordered(number: number, delimiter: chars[index]), index + 1 - position)
    }

    /// Every line of `chars`, split at newlines.
    static func lines(in chars: [UInt16]) -> [ComposerMarkdownLine] {
        var lines: [ComposerMarkdownLine] = []
        var start = 0
        for index in 0...chars.count where index == chars.count || chars[index] == .newline {
            lines.append(ComposerMarkdownLine(chars: chars, range: NSRange(location: start, length: index - start)))
            start = index + 1
        }
        return lines
    }

    /// The line containing `location`.
    static func line(in chars: [UInt16], containing location: Int) -> ComposerMarkdownLine {
        var start = min(location, chars.count)
        while start > 0, chars[start - 1] != .newline { start -= 1 }
        var end = min(location, chars.count)
        while end < chars.count, chars[end] != .newline { end += 1 }
        return ComposerMarkdownLine(chars: chars, range: NSRange(location: start, length: end - start))
    }

    /// Whether the line has nothing after its markers.
    func isBlank(in chars: [UInt16]) -> Bool {
        (contentStart..<end).allSatisfy { chars[$0] == .space || chars[$0] == .tab }
    }
}
