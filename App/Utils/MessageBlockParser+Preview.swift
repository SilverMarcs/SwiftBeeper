import Foundation

extension MessageBlockParser {
    /// A chat list preview's source with block Markdown flattened into plain
    /// lines, using the same rules as the timeline: headings and quotes keep
    /// their text, list items a bullet or number, tables their cells, and code
    /// its lines. Fences, rules and blank lines are dropped so the two preview
    /// lines show text. Inline Markdown is left for the preview renderer.
    static func previewSource(_ source: String) -> String {
        guard mayContainBlocks(source) || source.contains("\n\n") || source.contains("|") else { return source }
        var lines: [String] = []
        var openFence: String?
        for rawLine in source.split(whereSeparator: \.isNewline) {
            let line = rawLine.drop(while: \.isWhitespace)
            // A line like ```code``` is inline code, not a fence, and inside
            // code only the opening fence closes it.
            if let fence = fenceMarker(line), !line.dropFirst(fence.count).contains(fence),
               openFence == nil || openFence == fence {
                openFence = openFence == nil ? fence : nil
                continue
            }
            if openFence != nil {
                if let code = previewCodeLine(line) { lines.append(code) }
                continue
            }
            if let text = previewLine(line) { lines.append(text) }
        }
        let flattened = lines.joined(separator: "\n")
        // A message of bare syntax, such as a lone rule, shows as typed.
        return flattened.isEmpty ? source : flattened
    }

    /// A code line, wrapped as inline code so its punctuation isn't read as
    /// emphasis. A line holding backticks itself is left as written.
    private static func previewCodeLine(_ line: Substring) -> String? {
        let code = line.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return nil }
        return code.contains("`") ? code : "`\(code)`"
    }

    /// One line's text without its block syntax, or nil when the line is only
    /// syntax, such as a blank line, a rule or a table's header separator.
    private static func previewLine(_ line: Substring) -> String? {
        var line = line
        while let content = quoteContent(of: line) {
            line = content.drop(while: \.isWhitespace)
        }
        guard !line.allSatisfy(\.isWhitespace), !isRule(line), !isTableSeparator(line) else { return nil }
        if let heading = heading(line) {
            return String(heading.text)
        }
        if let item = listItem(line) {
            if item.number == nil, let task = taskMarker(item.text) {
                return "\(task) \(item.text.dropFirst(4))"
            }
            return "\(item.number.map { "\($0)." } ?? "•") \(item.text)"
        }
        if line.first == "|" {
            let cells = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return cells.isEmpty ? nil : cells.joined(separator: " · ")
        }
        return String(line.trimmingCharacters(in: .whitespaces))
    }

    /// A box for a task list item's `[ ] ` or `[x] `.
    private static func taskMarker(_ text: Substring) -> String? {
        switch text.prefix(4) {
        case "[ ] ": "☐"
        case "[x] ", "[X] ": "☑"
        default: nil
        }
    }

    /// A table's header separator, like `|---|:--:|`.
    private static func isTableSeparator(_ line: Substring) -> Bool {
        line.contains("|") && line.contains("-") && line.allSatisfy { "|-: \t".contains($0) }
    }
}
