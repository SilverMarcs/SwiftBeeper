#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Rich text pasted into the composer, written as the composer's Markdown:
/// bold, italic, strikethrough, code, links and lists keep their formatting
/// rather than pasting as plain text.
enum PastedMarkdown {
    /// Longer pastes stay plain text.
    static let maximumLength = 100_000

    /// The Markdown for `text`, or nil when it has no formatting to keep, so
    /// it pastes as plain text. Text all in a fixed-pitch font, as copied
    /// from a code editor or terminal, also pastes as plain text.
    static func markdown(from text: NSAttributedString) -> String? {
        let length = text.length
        guard length > 0, length <= maximumLength else { return nil }
        let chars = Array(text.string.utf16)
        var styles = [PastedMarkdownStyle](repeating: PastedMarkdownStyle(), count: length)
        text.enumerateAttributes(in: NSRange(location: 0, length: length)) { attributes, range, _ in
            let style = PastedMarkdownStyle(attributes)
            for index in range.location..<NSMaxRange(range) {
                styles[index] = style
            }
        }
        let visible = chars.indices.filter { !chars[$0].isMarkdownWhitespace && !isLineBreak(chars[$0]) }
        guard !visible.isEmpty, !visible.allSatisfy({ styles[$0].code }) else { return nil }

        let lines = lines(in: chars)
        for line in lines {
            trimLinks(of: line, in: &styles, chars: chars)
        }

        var output: [String] = []
        var list = ListState()
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if let codeEnd = codeBlockEnd(from: index, lines: lines, chars: chars, styles: styles, text: text) {
                let block = lines[index..<codeEnd].map { string(chars, $0) }
                output.append("```\n" + block.joined(separator: "\n") + "\n```")
                list = ListState()
                index = codeEnd
                continue
            }
            if let item = listItem(at: line, chars: chars, text: text) {
                output.append(list.prefix(for: item) + inline(chars, styles, item.contentStart..<line.upperBound))
            } else {
                list = ListState()
                output.append(inline(chars, styles, line))
            }
            index += 1
        }

        let markdown = cleaned(output.joined(separator: "\n"))
        let plain = cleaned(lines.map { string(chars, $0) }.joined(separator: "\n"))
        return markdown.isEmpty || markdown == plain ? nil : markdown
    }

    // MARK: - Lines

    private static func isLineBreak(_ char: UInt16) -> Bool {
        char == .newline || char == 0x0D || char == 0x2028 || char == 0x2029
    }

    /// Each line's characters, without its line break.
    private static func lines(in chars: [UInt16]) -> [Range<Int>] {
        var lines: [Range<Int>] = []
        var start = 0
        var index = 0
        while index < chars.count {
            if isLineBreak(chars[index]) {
                lines.append(start..<index)
                // \r\n is one break.
                if chars[index] == 0x0D, index + 1 < chars.count, chars[index + 1] == .newline { index += 1 }
                start = index + 1
            }
            index += 1
        }
        lines.append(start..<chars.count)
        return lines
    }

    static func string(_ chars: [UInt16], _ range: Range<Int>) -> String {
        String(decoding: chars[range], as: UTF16.self)
    }

    /// Without attachments' placeholder characters or trailing blank lines.
    private static func cleaned(_ markdown: String) -> String {
        var result = markdown.replacingOccurrences(of: "\u{FFFC}", with: "")
        while let last = result.last, last.isNewline || last == " " || last == "\t" {
            result.removeLast()
        }
        return result
    }

    // MARK: - Code blocks

    /// Whether the line has text, all of it in a fixed-pitch font.
    private static func isCodeLine(_ line: Range<Int>, chars: [UInt16], styles: [PastedMarkdownStyle]) -> Bool {
        let visible = line.filter { !chars[$0].isMarkdownWhitespace }
        return !visible.isEmpty && visible.allSatisfy { styles[$0].code }
    }

    /// Where the code block starting at `index` ends: the run of lines all in
    /// code, with any blank lines between them. Nil when the line isn't code.
    private static func codeBlockEnd(
        from index: Int, lines: [Range<Int>], chars: [UInt16], styles: [PastedMarkdownStyle], text: NSAttributedString
    ) -> Int? {
        guard isCodeLine(lines[index], chars: chars, styles: styles), listItem(at: lines[index], chars: chars, text: text) == nil else { return nil }
        var end = index + 1
        var candidate = end
        while candidate < lines.count {
            let line = lines[candidate]
            if line.allSatisfy({ chars[$0].isMarkdownWhitespace }) {
                candidate += 1
            } else if isCodeLine(line, chars: chars, styles: styles) {
                candidate += 1
                end = candidate
            } else {
                break
            }
        }
        // A fence inside the code would end the block early.
        let containsFence = lines[index..<end].contains { string(chars, $0).contains("```") }
        return containsFence ? nil : end
    }

    // MARK: - Lists

    struct ListItem {
        /// 1 for a top-level item, 2 for one nested in it, and so on.
        let depth: Int
        let isOrdered: Bool
        /// The number its marker shows, if it shows one.
        let number: Int?
        /// Where the item's text starts, after the marker the import drew.
        let contentStart: Int
    }

    /// The list item the line is, as rich text marks one: a paragraph in a
    /// text list, starting with its marker between tabs, `\t•\t`.
    private static func listItem(at line: Range<Int>, chars: [UInt16], text: NSAttributedString) -> ListItem? {
        guard !line.isEmpty,
              let style = text.attribute(.paragraphStyle, at: line.lowerBound, effectiveRange: nil) as? NSParagraphStyle,
              let list = style.textLists.last else { return nil }
        var markerStart = line.lowerBound
        while markerStart < line.upperBound, chars[markerStart] == .tab { markerStart += 1 }
        var contentStart = line.lowerBound
        var marker = ""
        if let tab = chars[markerStart..<min(markerStart + 16, line.upperBound)].firstIndex(of: .tab) {
            marker = string(chars, markerStart..<tab)
            contentStart = tab + 1
        }
        let number = Int(marker.filter(\.isNumber))
        return ListItem(depth: style.textLists.count, isOrdered: list.isOrdered, number: number, contentStart: contentStart)
    }

    /// Numbers ordered items and indents nested ones under their parent's
    /// text, as the composer's Tab does.
    struct ListState {
        /// The marker, with its space, of the latest item at each depth.
        private var markers: [String] = []
        private var counts: [Int] = []

        mutating func prefix(for item: ListItem) -> String {
            let depth = max(item.depth, 1)
            if markers.count >= depth {
                markers.removeSubrange(depth...)
                counts.removeSubrange(depth...)
            }
            while markers.count < depth - 1 {
                markers.append("- ")
                counts.append(0)
            }
            let previous = markers.count == depth ? counts[depth - 1] : 0
            let number = item.number ?? previous + 1
            let marker = item.isOrdered ? "\(number). " : "- "
            let indent = String(repeating: " ", count: markers.prefix(depth - 1).reduce(0) { $0 + $1.count })
            if markers.count == depth {
                markers[depth - 1] = marker
                counts[depth - 1] = number
            } else {
                markers.append(marker)
                counts.append(number)
            }
            return indent + marker
        }
    }
}
