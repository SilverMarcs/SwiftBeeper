import SwiftUI

extension EnvironmentValues {
    /// The signed-in user's Matrix ID. Message bodies highlight mentions of
    /// it so the reader can spot them in a busy group or thread; mentions of
    /// anyone else keep the ordinary link style.
    @Entry var selfMentionUserID: String?
}

/// `NSCache` stores objects, so the blocks are boxed.
private final class HighlightedBlocksBox {
    let blocks: [MessageBlock]
    init(_ blocks: [MessageBlock]) { self.blocks = blocks }
}

/// Only messages with mention links reach this cache, and their rows
/// rebuild as they scroll into view, so restyling is done once per body.
private let highlightedBlocksCache: NSCache<NSString, HighlightedBlocksBox> = {
    let cache = NSCache<NSString, HighlightedBlocksBox>()
    cache.countLimit = 500
    return cache
}()

extension String {
    /// `messageBlocks` with every mention of `userID` highlighted.
    func messageBlocks(highlightingMentionOf userID: String?) -> [MessageBlock] {
        highlighting(messageBlocks, mentionOf: userID, variant: "full")
    }

    /// `collapsedMessageBlocks` with every mention of `userID` highlighted.
    func collapsedMessageBlocks(highlightingMentionOf userID: String?) -> [MessageBlock]? {
        collapsedMessageBlocks.map { highlighting($0, mentionOf: userID, variant: "preview") }
    }

    /// `blocks`, parsed from this message Markdown, restyled. `variant` tells
    /// apart block sets from the same source in the cache.
    private func highlighting(_ blocks: [MessageBlock], mentionOf userID: String?, variant: String) -> [MessageBlock] {
        guard let userID, hasMentionLinks else { return blocks }
        let key = "\(variant)\u{0}\(userID)\u{0}\(self)" as NSString
        if let cached = highlightedBlocksCache.object(forKey: key) { return cached.blocks }
        let highlighted = blocks.map { $0.highlightingMention(of: userID) }
        highlightedBlocksCache.setObject(HighlightedBlocksBox(highlighted), forKey: key)
        return highlighted
    }
}

private extension MessageBlock {
    func highlightingMention(of userID: String) -> MessageBlock {
        switch self {
        case .text(let text):
            .text(text.highlightingMention(of: userID))
        case .quote(let blocks):
            .quote(blocks.map { $0.highlightingMention(of: userID) })
        case .heading(let level, let text):
            .heading(level: level, text.highlightingMention(of: userID))
        case .list(let items):
            .list(items.map { item in
                MessageListItem(marker: item.marker, blocks: item.blocks.map { $0.highlightingMention(of: userID) })
            })
        case .code, .rule:
            self
        }
    }
}

private extension AttributedString {
    /// Mentions of `userID` turn bold orange on an orange wash. SwiftUI
    /// colors every link with the view's tint, so the mention stops being a
    /// link; it would only open the reader's own profile anyway.
    func highlightingMention(of userID: String) -> AttributedString {
        var result = self
        for (link, range) in runs[\.link] {
            guard let link, MessageMentionLink(link)?.userID == userID else { continue }
            result[range].link = nil
            result[range].underlineStyle = nil
            result[range].foregroundColor = Color.orange
            result[range].backgroundColor = Color.orange.opacity(0.18)
            var intent = result[range].inlinePresentationIntent ?? []
            intent.insert(.stronglyEmphasized)
            result[range].inlinePresentationIntent = intent
        }
        return result
    }
}
