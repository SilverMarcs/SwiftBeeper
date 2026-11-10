import SwiftUI

/// Long message bodies collapse to a preview until the reader expands them.
///
/// On macOS a SwiftUI `Text` lays out and rasterizes its whole string when its
/// row scrolls into view, and text selection lays it out a second time, so
/// one very long message stalls scrolling for several frames (about 3ms per
/// 1,000 characters on an M1 Pro). Capping the preview keeps that cost per row
/// small, whatever the message length.
enum MessageCollapse {
    /// Bodies longer than either limit collapse.
    static let collapseCharacterCount = 2000
    static let collapseLineCount = 30
    /// What a collapsed body still shows.
    static let previewCharacterCount = 1000
    static let previewLineCount = 15
}

/// `NSCache` stores objects, so the optional preview is boxed. `nil` records
/// a body that stays whole.
private final class CollapsedBlocksBox {
    let blocks: [MessageBlock]?
    init(_ blocks: [MessageBlock]?) { self.blocks = blocks }
}

private let collapsedBlocksCache: NSCache<NSString, CollapsedBlocksBox> = {
    let cache = NSCache<NSString, CollapsedBlocksBox>()
    cache.countLimit = 2000
    return cache
}()

extension String {
    /// The collapsed preview of a long message body, or nil when the body is
    /// short enough to show whole.
    var collapsedMessageBlocks: [MessageBlock]? {
        // Too short for either limit; rows check this on every update.
        guard utf8.count > MessageCollapse.collapseLineCount else { return nil }
        let key = self as NSString
        if let cached = collapsedBlocksCache.object(forKey: key) { return cached.blocks }

        var blocks: [MessageBlock]?
        if count > MessageCollapse.collapseCharacterCount
            || reduce(0, { $1.isNewline ? $0 + 1 : $0 }) >= MessageCollapse.collapseLineCount {
            var budget = MessageCollapseBudget(
                characters: MessageCollapse.previewCharacterCount,
                lines: MessageCollapse.previewLineCount
            )
            let preview = budget.take(messageBlocks)
            // Markdown can render far shorter than its source, for example
            // links shown by their host; such a body keeps everything.
            if budget.didTruncate { blocks = preview }
        }
        collapsedBlocksCache.setObject(CollapsedBlocksBox(blocks), forKey: key)
        return blocks
    }
}

/// The characters and lines a collapsed preview has left, spent block by block.
private struct MessageCollapseBudget {
    var characters: Int
    var lines: Int
    private(set) var didTruncate = false

    /// The leading blocks that fit, the last one cut short when the budget runs out.
    mutating func take(_ blocks: [MessageBlock]) -> [MessageBlock] {
        var taken: [MessageBlock] = []
        for block in blocks {
            guard !didTruncate else { break }
            guard characters > 0, lines > 0 else {
                didTruncate = true
                break
            }
            switch block {
            case .text(let text):
                taken.append(.text(take(text)))
            case .quote(let content):
                let quoted = take(content)
                if !quoted.isEmpty { taken.append(.quote(quoted)) }
            }
            // The stack's spacing between blocks reads as a line.
            lines -= 1
        }
        return taken
    }

    /// The text up to where the budget runs out, ending on a word with an ellipsis.
    private mutating func take(_ text: AttributedString) -> AttributedString {
        let characterView = text.characters
        var index = characterView.startIndex
        while index < characterView.endIndex, characters > 0, lines > 0 {
            if characterView[index].isNewline { lines -= 1 }
            characters -= 1
            characterView.formIndex(after: &index)
        }
        guard index < characterView.endIndex else { return text }
        didTruncate = true

        // Prefer breaking after a nearby word over splitting one.
        var end = index
        let earliestBreak = characterView.index(index, offsetBy: -40, limitedBy: characterView.startIndex) ?? characterView.startIndex
        if let space = characterView[earliestBreak..<index].lastIndex(where: \.isWhitespace) {
            end = space
        }
        while end > characterView.startIndex, characterView[characterView.index(before: end)].isWhitespace {
            characterView.formIndex(before: &end)
        }

        var preview = AttributedString(text[text.startIndex..<end])
        var ellipsisAttributes = preview.runs.last?.attributes ?? AttributeContainer()
        ellipsisAttributes.link = nil
        ellipsisAttributes.underlineStyle = nil
        preview.append(AttributedString("…", attributes: ellipsisAttributes))
        return preview
    }
}
