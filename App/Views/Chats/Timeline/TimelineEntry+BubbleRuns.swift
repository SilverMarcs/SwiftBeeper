import Foundation

/// What parts a row's bubbles from the same sender's rows beside it. These
/// mirror what `MessageRowView` draws above and below the bubbles, so the
/// corners only tighten where two bubbles really meet.
extension TimelineEntry {
    /// Whether the row shows something above its bubbles: a reply's quote,
    /// the quoted thread a reply also sent to the chat belongs to, or the
    /// forwarded label. The sender's name only heads a group, which already
    /// starts a new run.
    static func breaksBubbleRunAbove(_ row: [Message], isThread: Bool) -> Bool {
        guard let message = row.first else { return false }
        return (!isThread && message.isThreadBroadcast == true)
            || message.linkedMessageID?.isEmpty == false
            || row.contains { $0.isForwarded == true }
    }

    /// Whether the row shows something below its bubbles: reaction pills, a
    /// thread's summary (in a thread, the "Also sent to" caption instead), or
    /// a failed send's caption.
    static func breaksBubbleRunBelow(_ row: [Message], isThread: Bool) -> Bool {
        guard let message = row.first else { return false }
        if isThread {
            if message.isThreadBroadcast == true { return true }
        } else if (message.thread?.replyCount ?? 0) > 0 {
            return true
        }
        if message.isSender, row.contains(where: { $0.deliveryStatus == .failed }) {
            return true
        }
        return row.contains { !$0.visibleReactions.isEmpty }
    }
}
