import Foundation

extension ComposerMarkdownEdit {
    enum LinePrefix {
        case quote
        case bullet
        case ordered
    }

    /// The lines the selection touches. A selection ending at a line's
    /// start, as a triple-click leaves it, doesn't take in that line.
    static func selectedLines(_ selection: NSRange, in chars: [UInt16]) -> [ComposerMarkdownLine] {
        var end = NSMaxRange(selection)
        if selection.length > 0, end > 0, chars[end - 1] == .newline { end -= 1 }
        var lines: [ComposerMarkdownLine] = []
        var location = selection.location
        repeat {
            let line = ComposerMarkdownLine.line(in: chars, containing: location)
            lines.append(line)
            location = line.end + 1
        } while location <= end && location <= chars.count
        return lines
    }

    /// Makes the selected lines a quote or list, or stops them being one
    /// when they all already are. Blank lines are left alone, unless there's
    /// nothing else, so an empty line can start a list.
    static func toggleLinePrefix(_ prefix: LinePrefix, in chars: [UInt16], selection: NSRange) -> ComposerMarkdownEdit {
        let lines = selectedLines(selection, in: chars)
        let filled = lines.filter { !($0.marker == nil && $0.isBlank(in: chars)) }
        let targets = filled.isEmpty ? lines : filled

        func has(_ line: ComposerMarkdownLine) -> Bool {
            switch (prefix, line.marker) {
            case (.quote, _): line.quoteDepth > 0
            case (.bullet, .bullet?), (.ordered, .ordered?): true
            default: false
            }
        }

        var replacements: [Replacement] = []
        if targets.allSatisfy(has) {
            for line in targets {
                switch prefix {
                case .quote:
                    replacements.append(Replacement(range: NSRange(location: line.range.location, length: line.quoteEnd - line.range.location), text: ""))
                case .bullet, .ordered:
                    if let marker = line.markerRange {
                        replacements.append(Replacement(range: NSRange(location: marker.location, length: line.contentStart - marker.location), text: ""))
                    }
                }
            }
        } else {
            for (number, line) in targets.enumerated() {
                switch prefix {
                case .quote:
                    if line.quoteDepth == 0 {
                        replacements.append(Replacement(range: NSRange(location: line.range.location, length: 0), text: "> "))
                    }
                case .bullet, .ordered:
                    let marker = prefix == .bullet ? "- " : "\(number + 1). "
                    if let existing = line.markerRange {
                        // A numbered list becomes bulleted, and the reverse.
                        replacements.append(Replacement(range: NSRange(location: existing.location, length: line.contentStart - existing.location), text: marker))
                    } else {
                        replacements.append(Replacement(range: NSRange(location: line.contentStart, length: 0), text: marker))
                    }
                }
            }
        }
        let start = map(selection.location, through: replacements, followsInsertions: true)
        let end = selection.length == 0 ? start : map(NSMaxRange(selection), through: replacements, followsInsertions: false)
        return ComposerMarkdownEdit(replacements: replacements, selection: NSRange(location: start, length: max(end - start, 0)))
    }

    /// Fences the selected lines as a code block, or removes the fences when
    /// the selection is already one.
    static func toggleCodeBlock(in chars: [UInt16], selection: NSRange) -> ComposerMarkdownEdit {
        let lines = selectedLines(selection, in: chars)
        guard let first = lines.first, let last = lines.last else {
            return ComposerMarkdownEdit(replacements: [], selection: selection)
        }
        let allLines = ComposerMarkdownLine.lines(in: chars)

        // Fences selected with the code, or just around it.
        if lines.count >= 2, isFence(first, in: chars), isFence(last, in: chars) {
            return removingFences(first, last, chars: chars, selection: selection)
        }
        if let above = allLines.last(where: { $0.end == first.range.location - 1 }),
           let below = allLines.first(where: { $0.range.location == last.end + 1 }),
           isFence(above, in: chars), isFence(below, in: chars) {
            return removingFences(above, below, chars: chars, selection: selection)
        }

        if selection.length == 0, first.isBlank(in: chars), first.marker == nil {
            return ComposerMarkdownEdit(
                replacements: [Replacement(range: first.range, text: "```\n\n```")],
                selection: NSRange(location: first.range.location + 4, length: 0)
            )
        }
        let replacements = [
            Replacement(range: NSRange(location: last.end, length: 0), text: "\n```"),
            Replacement(range: NSRange(location: first.range.location, length: 0), text: "```\n"),
        ]
        let start = map(first.range.location, through: replacements, followsInsertions: true)
        let end = map(last.end, through: replacements, followsInsertions: false)
        return ComposerMarkdownEdit(replacements: replacements, selection: NSRange(location: start, length: end - start))
    }

    private static func isFence(_ line: ComposerMarkdownLine, in chars: [UInt16]) -> Bool {
        let text = string(chars, line.range).trimmingCharacters(in: .whitespaces)
        return text.hasPrefix("```") || text.hasPrefix("~~~")
    }

    /// Deletes both fence lines with their newlines.
    private static func removingFences(
        _ opening: ComposerMarkdownLine,
        _ closing: ComposerMarkdownLine,
        chars: [UInt16],
        selection: NSRange
    ) -> ComposerMarkdownEdit {
        // An empty block goes in one piece, as its fences share a newline.
        if closing.range.location == opening.end + 1 {
            let both = NSRange(location: opening.range.location, length: closing.end - opening.range.location)
            return ComposerMarkdownEdit(
                replacements: [Replacement(range: both, text: "")],
                selection: NSRange(location: opening.range.location, length: 0)
            )
        }
        let closingRange = closing.range.location > 0
            ? NSRange(location: closing.range.location - 1, length: closing.range.length + 1)
            : closing.range
        let openingRange = NSRange(location: opening.range.location, length: min(opening.range.length + 1, chars.count - opening.range.location))
        let replacements = [
            Replacement(range: closingRange, text: ""),
            Replacement(range: openingRange, text: ""),
        ]
        let codeStart = NSMaxRange(openingRange)
        let codeEnd = closingRange.location
        let start = map(codeStart, through: replacements, followsInsertions: true)
        let end = map(max(codeEnd, codeStart), through: replacements, followsInsertions: false)
        return ComposerMarkdownEdit(replacements: replacements, selection: NSRange(location: start, length: max(end - start, 0)))
    }
}
