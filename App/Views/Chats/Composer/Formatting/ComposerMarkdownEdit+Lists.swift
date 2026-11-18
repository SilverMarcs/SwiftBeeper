import Foundation

extension ComposerMarkdownEdit {
    /// A new line that carries on the quote or list item the caret is in,
    /// as Slack's Shift-Return does. On an empty item or quote line it ends
    /// the list or quote instead, leaving the blank line that Markdown needs
    /// to stop the next line joining it. Nil means a plain new line.
    static func newline(in text: String, selection: NSRange) -> ComposerMarkdownEdit? {
        let chars = Array(text.utf16)
        guard selection.length == 0, selection.location <= chars.count else { return nil }
        let caret = selection.location
        let line = ComposerMarkdownLine.line(in: chars, containing: caret)
        guard line.marker != nil || line.quoteDepth > 0, caret >= line.contentStart else { return nil }
        if isInCodeBlock(line, chars: chars) { return nil }
        let quotePrefix = String(repeating: "> ", count: line.quoteDepth)

        if line.isBlank(in: chars) {
            if line.marker != nil, line.indent > 0, let outdent = outdent(line, in: chars) {
                return ComposerMarkdownEdit(
                    replacements: [outdent],
                    selection: NSRange(location: caret - (line.contentStart - line.quoteEnd) + outdent.text.utf16.count, length: 0)
                )
            }
            // A list item inside a quote ends the list but stays quoted.
            let ending = line.marker != nil && line.quoteDepth > 0 ? quotePrefix.trimmingCharacters(in: .whitespaces) + "\n" + quotePrefix : "\n"
            return ComposerMarkdownEdit(
                replacements: [Replacement(range: line.range, text: ending)],
                selection: NSRange(location: line.range.location + ending.utf16.count, length: 0)
            )
        }

        var continuation = "\n" + quotePrefix
        if let markerRange = line.markerRange, let marker = line.marker {
            continuation += string(chars, NSRange(location: line.quoteEnd, length: markerRange.location - line.quoteEnd))
            continuation += markerText(after: marker) + " "
        }
        return ComposerMarkdownEdit(
            replacements: [Replacement(range: selection, text: continuation)],
            selection: NSRange(location: caret + continuation.utf16.count, length: 0)
        )
    }

    /// Tab nests the selected list items under the item above them;
    /// Shift-Tab moves them back out. Nil when no selected line is a list
    /// item, so Tab keeps its usual meaning.
    static func indent(in text: String, selection: NSRange, outward: Bool) -> ComposerMarkdownEdit? {
        let chars = Array(text.utf16)
        guard NSMaxRange(selection) <= chars.count else { return nil }
        let lines = selectedLines(selection, in: chars).filter { $0.marker != nil }
        guard !lines.isEmpty else { return nil }
        let replacements = lines.compactMap { line in
            outward ? outdent(line, in: chars) : nest(line, in: chars)
        }
        let start = map(selection.location, through: replacements, followsInsertions: true)
        let end = selection.length == 0 ? start : map(NSMaxRange(selection), through: replacements, followsInsertions: false)
        return ComposerMarkdownEdit(replacements: replacements, selection: NSRange(location: start, length: max(end - start, 0)))
    }

    /// Indents the item to its sibling's text above, renumbering it from 1
    /// as the first item of the nested list.
    private static func nest(_ line: ComposerMarkdownLine, in chars: [UInt16]) -> Replacement? {
        guard let sibling = previousItem(before: line, in: chars, where: { $0.indent == line.indent }),
              let siblingMarker = sibling.markerRange, let marker = line.marker else { return nil }
        let target = line.indent + siblingMarker.length + 1
        let text: String
        switch marker {
        case .bullet(let character): text = String(decoding: [character], as: UTF16.self)
        case .ordered(_, let delimiter): text = "1" + String(decoding: [delimiter], as: UTF16.self)
        }
        return prefixReplacement(for: line, indent: target, marker: text)
    }

    /// Moves the item out to the level of the nearest item above it that's
    /// further out, continuing that item's numbering.
    private static func outdent(_ line: ComposerMarkdownLine, in chars: [UInt16]) -> Replacement? {
        guard line.indent > 0, let marker = line.marker else { return nil }
        let parent = previousItem(before: line, in: chars, where: { $0.indent < line.indent })
        let target = parent?.indent ?? 0
        let text: String
        switch (marker, parent?.marker) {
        case (.ordered(_, let delimiter), .ordered(let number, _)?):
            text = "\(number + 1)" + String(decoding: [delimiter], as: UTF16.self)
        default:
            text = markerText(of: marker)
        }
        return prefixReplacement(for: line, indent: target, marker: text)
    }

    /// Replaces the item's indentation and marker, keeping its quote.
    private static func prefixReplacement(for line: ComposerMarkdownLine, indent: Int, marker: String) -> Replacement {
        Replacement(
            range: NSRange(location: line.quoteEnd, length: line.contentStart - line.quoteEnd),
            text: String(repeating: " ", count: indent) + marker + " "
        )
    }

    /// The nearest list item above `line`, within its list, that matches.
    private static func previousItem(
        before line: ComposerMarkdownLine,
        in chars: [UInt16],
        where matches: (ComposerMarkdownLine) -> Bool
    ) -> ComposerMarkdownLine? {
        var location = line.range.location - 1
        while location >= 0 {
            let above = ComposerMarkdownLine.line(in: chars, containing: location)
            if above.marker == nil, above.isBlank(in: chars) { return nil }
            if above.marker != nil, matches(above) { return above }
            if above.marker != nil, above.indent < line.indent, !matches(above) { return nil }
            location = above.range.location - 1
        }
        return nil
    }

    private static func markerText(of marker: ComposerMarkdownLine.ListMarker) -> String {
        switch marker {
        case .bullet(let character): String(decoding: [character], as: UTF16.self)
        case .ordered(let number, let delimiter): "\(number)" + String(decoding: [delimiter], as: UTF16.self)
        }
    }

    private static func markerText(after marker: ComposerMarkdownLine.ListMarker) -> String {
        switch marker {
        case .bullet: markerText(of: marker)
        case .ordered(let number, let delimiter): markerText(of: .ordered(number: number + 1, delimiter: delimiter))
        }
    }

    /// Whether the line is inside a fenced code block, where `>` and `-`
    /// are just code.
    private static func isInCodeBlock(_ line: ComposerMarkdownLine, chars: [UInt16]) -> Bool {
        ComposerMarkdownParser.spans(in: string(chars, NSRange(location: 0, length: line.end)))
            .contains { $0.kind == .codeBlock && NSLocationInRange(line.range.location, $0.range) }
    }
}
