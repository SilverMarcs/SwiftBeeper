import Foundation

/// What parts an optimistic row's bubbles from the rows beside it, mirroring
/// `OutgoingMessageRowView` as `TimelineEntry`'s rules mirror `MessageRowView`.
extension OutgoingMessage {
    /// Whether the row shows a reply's quote, or the thread label and quote
    /// of a thread reply also sent to the chat, above its bubbles.
    func breaksBubbleRunAbove(isThread: Bool) -> Bool {
        (!isThread && broadcastThreadRootID != nil) || replyToMessageID?.isEmpty == false
    }

    /// Whether the row shows a failed send's caption below its bubbles.
    var breaksBubbleRunBelow: Bool {
        if case .failed = state { return true }
        return false
    }
}
