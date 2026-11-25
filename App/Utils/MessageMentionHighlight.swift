import SwiftUI

extension EnvironmentValues {
    /// The signed-in user's Matrix ID. Message bodies highlight mentions of
    /// it, and mentions of the whole chat, so the reader can spot them in a
    /// busy group or thread; mentions of anyone else keep the ordinary link
    /// style.
    @Entry var selfMentionUserID: String?
}

/// The mentions in an incoming message that address the reader: links to
/// their own Matrix ID and, when the message notifies the whole chat, its
/// @room, @all, @here, @channel or @everyone.
struct MessageMentionHighlight: Equatable {
    var userID: String?
    var room = false

    static let none = MessageMentionHighlight()

    /// Keeps differently highlighted copies of one body apart in the cache.
    fileprivate var cacheKey: String {
        "\(room ? "room" : "")\u{0}\(userID ?? "")"
    }
}

/// `NSCache` stores objects, so the blocks are boxed.
private final class HighlightedBlocksBox {
    let blocks: [MessageBlock]
    init(_ blocks: [MessageBlock]) { self.blocks = blocks }
}

/// Only messages that mention the reader reach this cache, and their rows
/// rebuild as they scroll into view, so restyling is done once per body.
private let highlightedBlocksCache: NSCache<NSString, HighlightedBlocksBox> = {
    let cache = NSCache<NSString, HighlightedBlocksBox>()
    cache.countLimit = 500
    return cache
}()

extension String {
    /// `messageBlocks` with the reader's mentions highlighted.
    func messageBlocks(highlighting highlight: MessageMentionHighlight) -> [MessageBlock] {
        highlighting(messageBlocks, highlight, variant: "full")
    }

    /// `collapsedMessageBlocks` with the reader's mentions highlighted.
    func collapsedMessageBlocks(highlighting highlight: MessageMentionHighlight) -> [MessageBlock]? {
        collapsedMessageBlocks.map { highlighting($0, highlight, variant: "preview") }
    }

    /// `blocks`, parsed from this message Markdown, restyled. `variant` tells
    /// apart block sets from the same source in the cache.
    private func highlighting(_ blocks: [MessageBlock], _ highlight: MessageMentionHighlight, variant: String) -> [MessageBlock] {
        var highlight = highlight
        if !hasMentionLinks { highlight.userID = nil }
        if highlight.room, !contains("@"), !contains("＠") { highlight.room = false }
        guard highlight != .none else { return blocks }
        let key = "\(variant)\u{0}\(highlight.cacheKey)\u{0}\(self)" as NSString
        if let cached = highlightedBlocksCache.object(forKey: key) { return cached.blocks }
        let highlighted = blocks.map { $0.highlighting(highlight) }
        highlightedBlocksCache.setObject(HighlightedBlocksBox(highlighted), forKey: key)
        return highlighted
    }
}

private extension MessageBlock {
    func highlighting(_ highlight: MessageMentionHighlight) -> MessageBlock {
        switch self {
        case .text(let text):
            .text(text.highlighting(highlight))
        case .quote(let blocks):
            .quote(blocks.map { $0.highlighting(highlight) })
        case .heading(let level, let text):
            .heading(level: level, text.highlighting(highlight))
        case .list(let items):
            .list(items.map { item in
                MessageListItem(marker: item.marker, blocks: item.blocks.map { $0.highlighting(highlight) })
            })
        case .code, .rule:
            self
        }
    }
}

/// The words a body uses for a mention of the whole chat: Matrix and the
/// Slack and Discord bridges write @room, WhatsApp writes @all, and other
/// networks may keep @here, @channel or @everyone. A word inside another
/// word or an email address doesn't count.
private let roomMentionPattern = try! NSRegularExpression(
    pattern: #"(?<![\p{L}\p{N}_.@＠])[@＠](?:room|all|here|channel|everyone)(?![\p{L}\p{N}_])"#,
    options: [.caseInsensitive]
)

private extension AttributedString {
    func highlighting(_ highlight: MessageMentionHighlight) -> AttributedString {
        var result = self
        if let userID = highlight.userID {
            result.highlightMentions(of: userID)
        }
        if highlight.room {
            result.highlightRoomMentions()
        }
        return result
    }

    /// Mentions of `userID`. SwiftUI colors every link with the view's tint,
    /// so the mention stops being a link; it would only open the reader's
    /// own profile anyway.
    mutating func highlightMentions(of userID: String) {
        for (link, range) in runs[\.link] {
            guard let link, MessageMentionLink(link)?.userID == userID else { continue }
            self[range].link = nil
            self[range].underlineStyle = nil
            highlightMention(in: range)
        }
    }

    /// The whole-chat mention words outside links and inline code. Only
    /// attributes change, so the matched indices stay valid.
    mutating func highlightRoomMentions() {
        let text = String(characters)
        let matches = roomMentionPattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard let stringRange = Range(match.range, in: text),
                  let lower = AttributedString.Index(stringRange.lowerBound, within: self),
                  let upper = AttributedString.Index(stringRange.upperBound, within: self) else { continue }
            let range = lower..<upper
            let isPlainText = self[range].runs.allSatisfy { run in
                run.link == nil && run.inlinePresentationIntent?.contains(.code) != true
            }
            if isPlainText {
                highlightMention(in: range)
            }
        }
    }

    /// A mention of the reader turns bold orange on an orange wash.
    mutating func highlightMention(in range: Range<AttributedString.Index>) {
        self[range].foregroundColor = Color.orange
        self[range].backgroundColor = Color.orange.opacity(0.18)
        var intent = self[range].inlinePresentationIntent ?? []
        intent.insert(.stronglyEmphasized)
        self[range].inlinePresentationIntent = intent
    }
}
