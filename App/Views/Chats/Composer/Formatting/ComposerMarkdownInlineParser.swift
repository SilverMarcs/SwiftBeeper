import Foundation

/// Finds inline Markdown in one paragraph: emphasis, strikethrough, code
/// spans, links and escapes, following CommonMark's rules for which
/// delimiters pair up, as the core's goldmark renderer does. The paragraph
/// may be several lines whose quote or list markers aren't part of it, so it
/// reads a list of segments joined by line breaks.
struct ComposerMarkdownInlineParser {
    /// A run of `*`, `_` or `~` that may open or close emphasis.
    private struct Delimiter {
        let character: UInt16
        /// Where the run's unused characters start, in the stream.
        var start: Int
        /// The run's unused characters.
        var count: Int
        let originalCount: Int
        let canOpen: Bool
        let canClose: Bool
    }

    /// Draft offsets of the stream's characters; `nil` is a line break.
    private let offsets: [Int?]
    private let chars: [UInt16]
    /// Draft offsets that read as ordinary letters, such as mentions.
    private let opaque: [Bool]
    private(set) var spans: [ComposerMarkdownSpan] = []
    private var delimiters: [Delimiter] = []

    /// Parses the paragraph made of `segments` of `chars`.
    static func spans(in chars: [UInt16], segments: [NSRange], opaque: [Bool]) -> [ComposerMarkdownSpan] {
        var parser = ComposerMarkdownInlineParser(chars: chars, segments: segments, opaque: opaque)
        parser.parse()
        return parser.spans
    }

    private init(chars: [UInt16], segments: [NSRange], opaque: [Bool]) {
        self.chars = chars
        self.opaque = opaque
        var offsets: [Int?] = []
        for (index, segment) in segments.enumerated() {
            if index > 0 { offsets.append(nil) }
            offsets.append(contentsOf: (segment.location..<NSMaxRange(segment)).map { Optional($0) })
        }
        self.offsets = offsets
    }

    /// Whether `index` is one of the stream's characters, not a line break.
    private func isInStream(_ index: Int) -> Bool {
        index >= 0 && index < offsets.count && offsets[index] != nil
    }

    /// The stream's character at `index`; outside it, a line break.
    private func character(at index: Int) -> UInt16 {
        guard index >= 0, index < offsets.count, let offset = offsets[index] else { return .newline }
        return opaque[offset] ? .letterA : chars[offset]
    }

    private mutating func parse() {
        var index = 0
        var brackets: [(index: Int, delimiterBottom: Int)] = []
        while index < offsets.count {
            let current = character(at: index)
            switch current {
            case .backslash where character(at: index + 1).isASCIIPunctuation && isInStream(index + 1):
                emit(.syntax, index..<index + 1, reveal: index..<index + 2)
                index += 2
            case .backtick:
                index = codeSpan(at: index)
            case .asterisk, .underscore, .tilde:
                index = delimiterRun(at: index)
            case .openingBracket:
                brackets.append((index, delimiters.count))
                index += 1
            case .closingBracket:
                if let open = brackets.popLast(), let end = linkDestinationEnd(after: index) {
                    processEmphasis(from: open.delimiterBottom)
                    delimiters.removeSubrange(open.delimiterBottom...)
                    emit(.syntax, open.index..<open.index + 1, reveal: open.index..<end)
                    emit(.link, open.index + 1..<index)
                    emit(.syntax, index..<end, reveal: open.index..<end)
                    // Links don't nest.
                    brackets.removeAll()
                    index = end
                } else {
                    index += 1
                }
            default:
                index += 1
            }
        }
        processEmphasis(from: 0)
    }

    /// A code span opened by the backtick run at `index`, closed by the next
    /// run of the same length. Returns where scanning continues.
    private mutating func codeSpan(at index: Int) -> Int {
        let length = runLength(at: index)
        var probe = index + length
        while probe < offsets.count {
            guard character(at: probe) == .backtick, offsets[probe] != nil else {
                probe += 1
                continue
            }
            let closing = runLength(at: probe)
            if closing == length {
                let construct = index..<probe + length
                emit(.syntax, index..<index + length, reveal: construct)
                emit(.code, index + length..<probe)
                emit(.syntax, probe..<probe + length, reveal: construct)
                return probe + length
            }
            probe += closing
        }
        return index + length
    }

    private func runLength(at index: Int) -> Int {
        let run = character(at: index)
        var end = index
        while end < offsets.count, offsets[end] != nil, character(at: end) == run { end += 1 }
        return end - index
    }

    /// Records the run at `index` as a delimiter, using CommonMark's
    /// flanking rules. Returns where scanning continues.
    private mutating func delimiterRun(at index: Int) -> Int {
        let run = character(at: index)
        let length = runLength(at: index)
        let before = character(at: index - 1)
        let after = character(at: index + length)
        let leftFlanking = !after.isMarkdownWhitespace
            && (!after.isMarkdownPunctuation || before.isMarkdownWhitespace || before.isMarkdownPunctuation)
        let rightFlanking = !before.isMarkdownWhitespace
            && (!before.isMarkdownPunctuation || after.isMarkdownWhitespace || after.isMarkdownPunctuation)
        let canOpen: Bool
        let canClose: Bool
        switch run {
        case .underscore:
            canOpen = leftFlanking && (!rightFlanking || before.isMarkdownPunctuation)
            canClose = rightFlanking && (!leftFlanking || after.isMarkdownPunctuation)
        case .tilde:
            // The core strikes through with exactly two tildes.
            guard length == 2 else { return index + length }
            canOpen = leftFlanking
            canClose = rightFlanking
        default:
            canOpen = leftFlanking
            canClose = rightFlanking
        }
        if canOpen || canClose {
            delimiters.append(Delimiter(
                character: run, start: index, count: length, originalCount: length,
                canOpen: canOpen, canClose: canClose
            ))
        }
        return index + length
    }

    /// For a `]` at `index` followed by `(…)`, the index after the `)`.
    private func linkDestinationEnd(after index: Int) -> Int? {
        guard character(at: index + 1) == .openingParenthesis, isInStream(index + 1) else { return nil }
        var depth = 0
        var probe = index + 2
        while probe < offsets.count, offsets[probe] != nil {
            switch character(at: probe) {
            case .backslash: probe += 1
            case .openingParenthesis: depth += 1
            case .closingParenthesis:
                if depth == 0 { return probe + 1 }
                depth -= 1
            default: break
            }
            probe += 1
        }
        return nil
    }

    /// Pairs the delimiters from `bottom` on, as CommonMark's "process
    /// emphasis" does.
    private mutating func processEmphasis(from bottom: Int) {
        var closerIndex = bottom
        while closerIndex < delimiters.count {
            let closer = delimiters[closerIndex]
            guard closer.canClose, closer.count > 0,
                  let openerIndex = opener(for: closer, before: closerIndex, bottom: bottom) else {
                closerIndex += 1
                continue
            }
            let opener = delimiters[openerIndex]
            let used = closer.character == .tilde ? 2 : (opener.count >= 2 && closer.count >= 2 ? 2 : 1)
            let openerUsedStart = opener.start + opener.count - used
            let construct = openerUsedStart..<closer.start + used
            emit(.syntax, openerUsedStart..<openerUsedStart + used, reveal: construct)
            emit(.syntax, closer.start..<closer.start + used, reveal: construct)
            let style: ComposerMarkdownSpan.Kind = closer.character == .tilde ? .strikethrough : (used == 2 ? .bold : .italic)
            emit(style, openerUsedStart + used..<closer.start)

            delimiters[openerIndex].count -= used
            delimiters[closerIndex].count -= used
            delimiters[closerIndex].start += used
            // Delimiters inside the pair can't pair with ones outside it.
            delimiters.removeSubrange(openerIndex + 1..<closerIndex)
            closerIndex = openerIndex + 1
            if delimiters[openerIndex].count == 0 {
                delimiters.remove(at: openerIndex)
                closerIndex -= 1
            }
            if delimiters[closerIndex].count == 0 {
                delimiters.remove(at: closerIndex)
            }
        }
    }

    private func opener(for closer: Delimiter, before closerIndex: Int, bottom: Int) -> Int? {
        var index = closerIndex - 1
        while index >= bottom {
            let candidate = delimiters[index]
            if candidate.character == closer.character, candidate.canOpen, candidate.count > 0 {
                if closer.character == .tilde {
                    if candidate.count == 2, closer.count == 2 { return index }
                } else {
                    // CommonMark's "rule of three".
                    let isOddMatch = (candidate.canClose || closer.canOpen)
                        && (candidate.originalCount + closer.originalCount) % 3 == 0
                        && !(candidate.originalCount % 3 == 0 && closer.originalCount % 3 == 0)
                    if !isOddMatch { return index }
                }
            }
            index -= 1
        }
        return nil
    }

    /// Adds a span over stream positions `range`, split where the stream
    /// skips lines' markers.
    private mutating func emit(_ kind: ComposerMarkdownSpan.Kind, _ range: Range<Int>, reveal: Range<Int>? = nil) {
        let revealRange = reveal.flatMap(draftRange)
        var start: Int?
        var previous: Int?
        for index in range {
            guard isInStream(index), let offset = offsets[index] else { continue }
            if let previousOffset = previous, offset == previousOffset + 1 {
                previous = offset
                continue
            }
            if let start, let previous {
                spans.append(ComposerMarkdownSpan(kind: kind, range: NSRange(location: start, length: previous + 1 - start), reveal: revealRange))
            }
            start = offset
            previous = offset
        }
        if let start, let previous {
            spans.append(ComposerMarkdownSpan(kind: kind, range: NSRange(location: start, length: previous + 1 - start), reveal: revealRange))
        }
    }

    /// The draft range from the first to the last character of stream
    /// positions `range`, taking in any line markers between.
    private func draftRange(_ range: Range<Int>) -> NSRange? {
        guard let first = range.lazy.compactMap({ self.isInStream($0) ? self.offsets[$0] : nil }).first,
              let last = range.reversed().lazy.compactMap({ self.isInStream($0) ? self.offsets[$0] : nil }).first else { return nil }
        return NSRange(location: first, length: last + 1 - first)
    }
}
