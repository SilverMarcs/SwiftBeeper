import Foundation

/// A change to the draft's Markdown, worked out from its text and selection
/// so the editor only has to make it. Changes are small insertions and
/// deletions rather than one replacement, so mentions outside them keep
/// their identities, and undo restores them as one step.
struct ComposerMarkdownEdit: Equatable {
    struct Replacement: Equatable {
        let range: NSRange
        let text: String
    }

    /// Ranges in the original draft, in descending order, so making each in
    /// turn leaves the ones still to come where they were.
    let replacements: [Replacement]
    /// The selection once every replacement is made.
    let selection: NSRange

    /// Sorts `replacements` for making in turn. Of two at the same place,
    /// the one listed later ends up first in the text.
    init(replacements: [Replacement], selection: NSRange) {
        self.replacements = replacements.enumerated()
            .sorted { lhs, rhs in
                lhs.element.range.location != rhs.element.range.location
                    ? lhs.element.range.location > rhs.element.range.location
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
        self.selection = selection
    }

    /// The edit `format` makes to `text` with `selection`.
    static func applying(_ format: ComposerFormat, to text: String, selection: NSRange) -> ComposerMarkdownEdit? {
        let chars = Array(text.utf16)
        guard NSMaxRange(selection) <= chars.count else { return nil }
        switch format {
        case .bold: return toggleInline(.asterisk, width: 2, in: chars, selection: selection)
        // `*` rather than `_`: an underscore typed right after a mention would end it.
        case .italic: return toggleInline(.asterisk, width: 1, in: chars, selection: selection)
        case .strikethrough: return toggleInline(.tilde, width: 2, in: chars, selection: selection)
        case .code:
            let isMultiline = (selection.location..<NSMaxRange(selection)).contains { chars[$0] == .newline }
            return isMultiline
                ? toggleCodeBlock(in: chars, selection: selection)
                : toggleInline(.backtick, width: 1, in: chars, selection: selection)
        case .codeBlock: return toggleCodeBlock(in: chars, selection: selection)
        case .link: return link(in: chars, selection: selection)
        case .quote: return toggleLinePrefix(.quote, in: chars, selection: selection)
        case .bulletedList: return toggleLinePrefix(.bullet, in: chars, selection: selection)
        case .numberedList: return toggleLinePrefix(.ordered, in: chars, selection: selection)
        }
    }

    /// Where `location` in the original draft lands once `replacements` are
    /// made. Text inserted exactly there lands before it when
    /// `followsInsertions`, and after it otherwise.
    static func map(_ location: Int, through replacements: [Replacement], followsInsertions: Bool) -> Int {
        var delta = 0
        for replacement in replacements {
            let range = replacement.range
            let inserted = replacement.text.utf16.count
            if NSMaxRange(range) < location || (NSMaxRange(range) == location && (range.length > 0 || followsInsertions)) {
                delta += inserted - range.length
            } else if range.location < location {
                // Inside replaced text: its start.
                delta += range.location - location
            }
        }
        return location + delta
    }

    static func string(_ chars: [UInt16], _ range: NSRange) -> String {
        String(decoding: chars[range.location..<NSMaxRange(range)], as: UTF16.self)
    }
}
