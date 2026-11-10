import Foundation

/// Splits message Markdown into `MessageBlock`s line by line.
///
/// Foundation's `.full` Markdown syntax would also recognize blocks, but it
/// folds single line breaks into spaces, which chat text relies on. Scanning
/// lines keeps every other line exactly as the inline renderer shows it.
enum MessageBlockParser {
    /// Cheap pre-check: text where no line starts with a block marker is a
    /// single text block and skips line scanning.
    static func mayContainBlocks(_ source: String) -> Bool {
        var atLineStart = true
        var leadingSpaces = 0
        var bytes = source.utf8.makeIterator()
        while let byte = bytes.next() {
            if byte == UInt8(ascii: "\n") {
                atLineStart = true
                leadingSpaces = 0
                continue
            }
            guard atLineStart else { continue }
            if byte == UInt8(ascii: " "), leadingSpaces < 3 {
                leadingSpaces += 1
                continue
            }
            atLineStart = false
            switch byte {
            // Quotes, headings, bullets, fences, rules and numbered items.
            case UInt8(ascii: ">"), UInt8(ascii: "#"), UInt8(ascii: "*"), UInt8(ascii: "-"),
                 UInt8(ascii: "+"), UInt8(ascii: "`"), UInt8(ascii: "_"), UInt8(ascii: "0")...UInt8(ascii: "9"),
                 0xE2: // The first byte of "•".
                return true
            default:
                continue
            }
        }
        return false
    }

    static func blocks(in source: String) -> [MessageBlock] {
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        return blocks(in: lines[...], depth: 0)
    }

    private static func blocks(in lines: ArraySlice<Substring>, depth: Int) -> [MessageBlock] {
        var blocks: [MessageBlock] = []
        var textLines: [Substring] = []

        func flushText() {
            defer { textLines.removeAll() }
            // Blank lines around a block only separate it; the stack spaces blocks.
            let text = textLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            guard !text.isEmpty else { return }
            blocks.append(.text(text.messageAttributed))
        }

        var index = lines.startIndex
        while index < lines.endIndex {
            let line = lines[index]

            if let fence = fenceMarker(line) {
                // Everything up to the closing fence, or the end, is code.
                var end = lines.index(after: index)
                while end < lines.endIndex, fenceMarker(lines[end]) != fence {
                    end = lines.index(after: end)
                }
                flushText()
                blocks.append(.code(lines[lines.index(after: index)..<end].joined(separator: "\n")))
                index = end < lines.endIndex ? lines.index(after: end) : end
                continue
            }

            if quoteContent(of: line) != nil {
                var quoteLines: [Substring] = []
                while index < lines.endIndex, let content = quoteContent(of: lines[index]) {
                    quoteLines.append(content)
                    index = lines.index(after: index)
                }
                flushText()
                let content = Self.blocks(in: quoteLines[...], depth: depth)
                if !content.isEmpty { blocks.append(.quote(content)) }
                continue
            }

            if let heading = heading(line) {
                flushText()
                blocks.append(.heading(level: heading.level, String(heading.text).messageAttributed))
                index = lines.index(after: index)
                continue
            }

            if isRule(line) {
                flushText()
                blocks.append(.rule)
                index = lines.index(after: index)
                continue
            }

            if listItem(line) != nil {
                flushText()
                let (items, end) = list(from: index, in: lines, depth: depth)
                blocks.append(.list(items))
                index = end
                continue
            }

            textLines.append(line)
            index = lines.index(after: index)
        }
        flushText()
        return blocks
    }

    /// The items of the list starting at `start`, and the line after it. An
    /// item continues over lines indented under its text, which may hold a
    /// nested list.
    private static func list(
        from start: Int,
        in lines: ArraySlice<Substring>,
        depth: Int
    ) -> (items: [MessageListItem], end: Int) {
        var items: [MessageListItem] = []
        var index = start
        while index < lines.endIndex, let item = listItem(lines[index]) {
            var itemLines = [item.text]
            index = lines.index(after: index)
            while index < lines.endIndex {
                let next = lines[index]
                let indent = next.prefix { $0 == " " }.count
                guard indent >= 2, !next.allSatisfy(\.isWhitespace) else { break }
                itemLines.append(next.dropFirst(min(indent, item.contentIndent)))
                index = lines.index(after: index)
            }
            let marker = item.number.map { "\($0)." } ?? bullet(forDepth: depth)
            items.append(MessageListItem(marker: marker, blocks: blocks(in: itemLines[...], depth: depth + 1)))
        }
        return (items, index)
    }

    private static func bullet(forDepth depth: Int) -> String {
        switch depth {
        case 0: "•"
        case 1: "◦"
        default: "▪"
        }
    }

    /// A list line's number, when ordered, its text, and how far its text is
    /// indented. Bullets are `*`, `-`, `+` or `•` followed by a space.
    private static func listItem(_ line: Substring) -> (number: Int?, text: Substring, contentIndent: Int)? {
        let indent = line.prefix { $0 == " " }.count
        guard indent <= 3 else { return nil }
        let rest = line.dropFirst(indent)
        guard let first = rest.first else { return nil }
        if "*-+•".contains(first) {
            let afterMarker = rest.dropFirst()
            guard afterMarker.first == " " else { return nil }
            let text = afterMarker.drop { $0 == " " }
            guard !text.isEmpty else { return nil }
            return (nil, text, indent + rest.count - text.count)
        }
        let digits = rest.prefix(while: \.isASCIIDigit)
        guard (1...9).contains(digits.count), let number = Int(digits) else { return nil }
        let afterDigits = rest.dropFirst(digits.count)
        guard let delimiter = afterDigits.first, delimiter == "." || delimiter == ")",
              afterDigits.dropFirst().first == " " else { return nil }
        let text = afterDigits.dropFirst().drop { $0 == " " }
        guard !text.isEmpty else { return nil }
        return (number, text, indent + rest.count - text.count)
    }

    /// A heading's level and text: one to six `#` and a space.
    private static func heading(_ line: Substring) -> (level: Int, text: Substring)? {
        let indent = line.prefix { $0 == " " }.count
        guard indent <= 3 else { return nil }
        let rest = line.dropFirst(indent)
        let hashes = rest.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), rest.dropFirst(hashes).first == " " else { return nil }
        let text = rest.dropFirst(hashes + 1).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (hashes, Substring(text))
    }

    /// Three or more of the same `-`, `*` or `_` and nothing else.
    private static func isRule(_ line: Substring) -> Bool {
        let marks = line.filter { !$0.isWhitespace }
        guard marks.count >= 3, let first = marks.first, "-*_".contains(first) else { return false }
        return marks.allSatisfy { $0 == first }
    }

    /// The fence a line opens or closes, such as "```".
    private static func fenceMarker(_ line: Substring) -> String? {
        let trimmed = line.drop { $0 == " " }
        let ticks = trimmed.prefix { $0 == "`" }.count
        return ticks >= 3 ? String(repeating: "`", count: ticks) : nil
    }

    /// The text after a line's `> ` marker, or nil when the line isn't quoted.
    /// Up to three leading spaces are allowed, as in CommonMark. Unlike
    /// CommonMark, a space (or another `>` for nesting) must follow the marker
    /// so emoticons such as `>_<` or `>:(` starting a message stay plain text.
    private static func quoteContent(of line: Substring) -> Substring? {
        let indent = line.prefix { $0 == " " }.count
        guard indent <= 3 else { return nil }
        let marked = line.dropFirst(indent)
        guard marked.first == ">" else { return nil }
        let rest = marked.dropFirst()
        switch rest.first {
        case nil, ">": return rest
        case " ": return rest.dropFirst()
        default: return nil
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
