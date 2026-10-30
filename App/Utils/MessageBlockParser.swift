import Foundation

/// Splits message Markdown into `MessageBlock`s line by line.
///
/// Foundation's `.full` Markdown syntax would also recognize blocks, but it
/// folds single line breaks into spaces and drops list markers, both of which
/// chat text relies on. Scanning lines keeps every other line exactly as the
/// inline renderer shows it today.
enum MessageBlockParser {
    /// Cheap pre-check: text without any block marker is a single text block
    /// and skips line scanning.
    static func mayContainBlocks(_ source: String) -> Bool {
        source.contains(">")
    }

    static func blocks(in source: String) -> [MessageBlock] {
        var blocks: [MessageBlock] = []
        var textLines: [Substring] = []
        var quoteLines: [Substring] = []

        func flushText() {
            defer { textLines.removeAll() }
            // Blank lines around a block only separate it; the stack spaces blocks.
            let text = textLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            guard !text.isEmpty else { return }
            blocks.append(.text(text.messageAttributed))
        }

        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            defer { quoteLines.removeAll() }
            let content = Self.blocks(in: quoteLines.joined(separator: "\n"))
            guard !content.isEmpty else { return }
            blocks.append(.quote(content))
        }

        for line in source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if let content = quoteContent(of: line) {
                flushText()
                quoteLines.append(content)
            } else {
                flushQuote()
                textLines.append(line)
            }
        }
        flushText()
        flushQuote()
        return blocks
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
