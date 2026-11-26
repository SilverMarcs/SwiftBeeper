import Foundation

extension PastedMarkdown {
    /// Emphasis the Markdown writes as markers around the text.
    private enum Emphasis: CaseIterable {
        case bold, italic, strikethrough

        var markup: String {
            switch self {
            case .bold: "**"
            // `*` rather than `_`, as the Format menu writes it.
            case .italic: "*"
            case .strikethrough: "~~"
            }
        }

        var keyPath: KeyPath<PastedMarkdownStyle, Bool> {
            switch self {
            case .bold: \.bold
            case .italic: \.italic
            case .strikethrough: \.strikethrough
            }
        }
    }

    /// Moves the whitespace at either end of each link out of it, so its
    /// text doesn't start or end with a space. `emphasized` does the same
    /// for emphasis as it writes the markers.
    static func trimLinks(of line: Range<Int>, in styles: inout [PastedMarkdownStyle], chars: [UInt16]) {
        var index = line.lowerBound
        while index < line.upperBound {
            guard let link = styles[index].link else {
                index += 1
                continue
            }
            var end = index + 1
            while end < line.upperBound, styles[end].link == link { end += 1 }
            var start = index
            while start < end, chars[start].isMarkdownWhitespace {
                styles[start].link = nil
                start += 1
            }
            var last = end
            while last > start, chars[last - 1].isMarkdownWhitespace {
                styles[last - 1].link = nil
                last -= 1
            }
            index = end
        }
    }

    /// The range's text with its links and emphasis in Markdown.
    static func inline(_ chars: [UInt16], _ styles: [PastedMarkdownStyle], _ range: Range<Int>) -> String {
        var output = ""
        var index = range.lowerBound
        while index < range.upperBound {
            let link = styles[index].link
            var end = index + 1
            while end < range.upperBound, styles[end].link == link { end += 1 }
            let text = emphasized(chars, styles, index..<end)
            let label = string(chars, index..<end)
            if let link, !isAddress(link, writtenAs: label) {
                output += "[\(text)](\(escaped(link)))"
            } else {
                output += text
            }
            index = end
        }
        return output
    }

    /// Whether the link's text is its address, which pastes as it is and is
    /// linked when sent.
    private static func isAddress(_ link: String, writtenAs label: String) -> Bool {
        func normalized(_ address: String) -> String {
            var address = address.lowercased()
            if address.hasPrefix("mailto:") { address.removeFirst("mailto:".count) }
            while address.hasSuffix("/") { address.removeLast() }
            return address
        }
        return normalized(link) == normalized(label)
    }

    /// Parentheses and spaces would end the link's destination early.
    private static func escaped(_ link: String) -> String {
        link.replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
    }

    /// The range's text with its emphasis and code in Markdown. Markers open
    /// just before text and close just after it, never beside whitespace.
    private static func emphasized(_ chars: [UInt16], _ styles: [PastedMarkdownStyle], _ range: Range<Int>) -> String {
        var output = ""
        var pendingWhitespace = ""
        var open: [Emphasis] = []
        var index = range.lowerBound
        while index < range.upperBound {
            let style = styles[index]
            var end = index + 1
            while end < range.upperBound, sameEmphasis(styles[end], style) { end += 1 }
            let segment = index..<end
            index = end

            var textStart = segment.lowerBound
            while textStart < segment.upperBound, chars[textStart].isMarkdownWhitespace { textStart += 1 }
            guard textStart < segment.upperBound else {
                pendingWhitespace += string(chars, segment)
                continue
            }
            var textEnd = segment.upperBound
            while chars[textEnd - 1].isMarkdownWhitespace { textEnd -= 1 }

            let wanted = Emphasis.allCases.filter { style[keyPath: $0.keyPath] }
            if let firstEnding = open.firstIndex(where: { !wanted.contains($0) }) {
                output += open[firstEnding...].reversed().map(\.markup).joined()
                open.removeSubrange(firstEnding...)
            }
            output += pendingWhitespace + string(chars, segment.lowerBound..<textStart)
            // What lasts longer opens first, so it closes last.
            let opening = wanted.filter { !open.contains($0) }
                .sorted { extent(of: $0, from: segment.lowerBound, in: styles, upTo: range.upperBound) > extent(of: $1, from: segment.lowerBound, in: styles, upTo: range.upperBound) }
            output += opening.map(\.markup).joined()
            open += opening
            let text = string(chars, textStart..<textEnd)
            output += style.code && !text.contains("`") ? "`\(text)`" : text
            pendingWhitespace = string(chars, textEnd..<segment.upperBound)
        }
        output += open.reversed().map(\.markup).joined() + pendingWhitespace
        return output
    }

    private static func sameEmphasis(_ lhs: PastedMarkdownStyle, _ rhs: PastedMarkdownStyle) -> Bool {
        lhs.bold == rhs.bold && lhs.italic == rhs.italic && lhs.strikethrough == rhs.strikethrough && lhs.code == rhs.code
    }

    private static func extent(of emphasis: Emphasis, from start: Int, in styles: [PastedMarkdownStyle], upTo end: Int) -> Int {
        var index = start
        while index < end, styles[index][keyPath: emphasis.keyPath] { index += 1 }
        return index - start
    }
}
