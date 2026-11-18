import Foundation

/// Finds the Markdown in a draft the way the core will read it when sending:
/// code blocks, quotes, headings, lists and rules line by line, then each
/// paragraph's inline formatting. It follows goldmark's CommonMark rules for
/// the cases chat text meets, such as a quote continuing onto an unmarked
/// line, so the composer shows what will actually be sent.
struct ComposerMarkdownParser {
    /// What the previous line was, which decides how the next one reads.
    private enum Context {
        case blank
        /// Text of a paragraph outside any quote or list.
        case paragraph
        case listItem
        case quote
        /// A heading, rule or code block, which a following line can't continue.
        case closed
    }

    private struct Fence {
        let character: UInt16
        let length: Int
    }

    private let chars: [UInt16]
    private let opaque: [Bool]
    private var spans: [ComposerMarkdownSpan] = []
    /// The current paragraph's text, one segment per line.
    private var paragraph: [NSRange] = []
    private var context = Context.blank
    private var fence: Fence?
    /// Whether indented lines continue a list item rather than starting code.
    private var isInList = false

    /// The draft's Markdown spans. Text in `opaque` ranges, such as
    /// mentions, reads as ordinary letters.
    static func spans(in text: String, opaque: [NSRange] = []) -> [ComposerMarkdownSpan] {
        let chars = Array(text.utf16)
        var opaqueOffsets = [Bool](repeating: false, count: chars.count)
        for range in opaque where range.location >= 0 && NSMaxRange(range) <= chars.count {
            for offset in range.location..<NSMaxRange(range) { opaqueOffsets[offset] = true }
        }
        var parser = ComposerMarkdownParser(chars: chars, opaque: opaqueOffsets)
        for line in ComposerMarkdownLine.lines(in: chars) {
            parser.read(line)
        }
        parser.endParagraph()
        return parser.spans
    }

    private init(chars: [UInt16], opaque: [Bool]) {
        self.chars = chars
        self.opaque = opaque
    }

    private mutating func read(_ line: ComposerMarkdownLine) {
        if let fence {
            readCode(line, in: fence)
            return
        }
        let quoted = line.quoteDepth > 0
        if quoted {
            add(.syntax, NSRange(location: line.range.location, length: line.quoteEnd - line.range.location), reveal: line.range)
            add(.quoteLine, line.range)
        }
        let isBlank = line.marker == nil && line.isBlank(in: chars)
        if isBlank {
            endParagraph()
            context = .blank
            return
        }
        // Lines continuing a quote's paragraph without `>` stay in the quote.
        let isLazyQuote = !quoted && context == .quote
        let bodyStart = line.quoteEnd + min(line.indent, 3)

        if line.indent < 4, let opened = openingFence(at: line.quoteEnd, end: line.end) {
            endParagraph()
            add(.syntax, line.range)
            fence = opened
            context = .closed
            return
        }
        if line.indent < 4, setextUnderline(in: line), context == .paragraph, !quoted {
            for segment in paragraph { add(.heading, segment) }
            endParagraph()
            add(.syntax, line.range)
            context = .closed
            return
        }
        if line.indent < 4, isThematicBreak(line) {
            endParagraph()
            add(.syntax, line.range)
            context = .closed
            isInList = false
            return
        }
        if line.indent < 4, let hashes = headingMarker(in: line) {
            endParagraph()
            add(.syntax, NSRange(location: line.quoteEnd, length: hashes.upperBound - line.quoteEnd), reveal: line.range)
            let text = NSRange(location: hashes.upperBound, length: line.end - hashes.upperBound)
            add(.heading, text)
            paragraph = [text]
            endParagraph()
            context = .closed
            isInList = false
            return
        }
        if let markerRange = line.markerRange, startsListItem(line) {
            endParagraph()
            add(.listMarker, markerRange)
            if quoted { add(.quote, line.contentRange) }
            paragraph = [line.contentRange]
            context = .listItem
            isInList = true
            return
        }

        // Plain text: a paragraph's next line, or the start of a new block.
        let text = NSRange(location: bodyStart, length: line.end - bodyStart)
        // A `>` line starts a quote, ending a paragraph or list item.
        if quoted, context == .paragraph || context == .listItem {
            endParagraph()
            context = .blank
        }
        switch context {
        case .paragraph, .listItem, .quote:
            paragraph.append(text)
            if quoted || isLazyQuote { add(.quote, text) }
            if isLazyQuote { add(.quoteLine, line.range) }
        case .blank, .closed:
            if line.indent >= 4, !quoted, !(isInList && context == .blank) {
                add(.codeBlock, line.range)
                context = .closed
                return
            }
            if line.indent < 2 { isInList = false }
            paragraph = [text]
            if quoted { add(.quote, text) }
            context = quoted ? .quote : (isInList ? .listItem : .paragraph)
        }
    }

    private mutating func readCode(_ line: ComposerMarkdownLine, in fence: Fence) {
        if isClosingFence(line, for: fence) {
            add(.syntax, line.range)
            self.fence = nil
            context = .closed
        } else {
            add(.codeBlock, line.range)
        }
    }

    /// Styles the finished paragraph's inline formatting.
    mutating func endParagraph() {
        guard !paragraph.isEmpty else { return }
        spans += ComposerMarkdownInlineParser.spans(in: chars, segments: paragraph, opaque: opaque)
        paragraph = []
    }

    private mutating func add(_ kind: ComposerMarkdownSpan.Kind, _ range: NSRange, reveal: NSRange? = nil) {
        guard range.length > 0 else { return }
        spans.append(ComposerMarkdownSpan(kind: kind, range: range, reveal: reveal))
    }

    // MARK: - Line kinds

    /// A list item may interrupt a paragraph only when it has text, and an
    /// ordered one only when it starts at 1.
    private func startsListItem(_ line: ComposerMarkdownLine) -> Bool {
        guard line.indent < 4 || isInList else { return false }
        guard context == .paragraph else { return true }
        if line.isBlank(in: chars) { return false }
        if case .ordered(let number, _) = line.marker, number != 1 { return false }
        return true
    }

    private func openingFence(at start: Int, end: Int) -> Fence? {
        var position = start
        while position < end, chars[position] == .space { position += 1 }
        guard position < end, chars[position] == .backtick || chars[position] == .tilde else { return nil }
        let character = chars[position]
        var length = 0
        while position < end, chars[position] == character {
            length += 1
            position += 1
        }
        guard length >= 3 else { return nil }
        // A backtick fence's info string can't contain backticks.
        if character == .backtick, (position..<end).contains(where: { chars[$0] == .backtick }) { return nil }
        return Fence(character: character, length: length)
    }

    private func isClosingFence(_ line: ComposerMarkdownLine, for fence: Fence) -> Bool {
        var position = line.range.location
        while position < line.end, position - line.range.location < 3, chars[position] == .space { position += 1 }
        var length = 0
        while position < line.end, chars[position] == fence.character {
            length += 1
            position += 1
        }
        guard length >= fence.length else { return false }
        return (position..<line.end).allSatisfy { chars[$0] == .space }
    }

    /// `===` or `---`, which turns the paragraph above into a heading.
    private func setextUnderline(in line: ComposerMarkdownLine) -> Bool {
        let body = trimmedBody(of: line)
        guard let first = body.first, first == .equals || first == .hyphen else { return false }
        return body.allSatisfy { $0 == first }
    }

    /// Three or more of the same `-`, `*` or `_`, with only spaces between.
    private func isThematicBreak(_ line: ComposerMarkdownLine) -> Bool {
        let body = trimmedBody(of: line).filter { $0 != .space && $0 != .tab }
        guard let first = body.first, first == .hyphen || first == .asterisk || first == .underscore else { return false }
        return body.count >= 3 && body.allSatisfy { $0 == first }
    }

    /// The line after its quote markers and indentation, without trailing spaces.
    private func trimmedBody(of line: ComposerMarkdownLine) -> ArraySlice<UInt16> {
        var start = line.quoteEnd
        while start < line.end, chars[start] == .space || chars[start] == .tab { start += 1 }
        var end = line.end
        while end > start, chars[end - 1] == .space || chars[end - 1] == .tab { end -= 1 }
        return chars[start..<end]
    }

    /// For an ATX heading, the range of its `#`s and the spaces after them.
    private func headingMarker(in line: ComposerMarkdownLine) -> Range<Int>? {
        var position = line.quoteEnd
        while position < line.end, chars[position] == .space { position += 1 }
        let start = position
        while position < line.end, chars[position] == .hash { position += 1 }
        let count = position - start
        guard (1...6).contains(count), position == line.end || chars[position] == .space else { return nil }
        while position < line.end, chars[position] == .space { position += 1 }
        return start..<position
    }
}
