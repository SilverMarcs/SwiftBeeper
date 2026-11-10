import Foundation

/// Grouping decisions for an optimistic (not yet server-confirmed) row, computed
/// with the same rules the canonical timeline uses so the bubble doesn't visibly
/// re-group when the server's version replaces it.
struct OutgoingTimelineEntry: Identifiable, Equatable {
    let message: OutgoingMessage
    let showsTimestamp: Bool
    /// Matches `TimelineEntry.startsSenderRun`: only the first optimistic row can
    /// follow someone else's message.
    let startsSenderRun: Bool
    /// The quoted message for a reply, resolved from the canonical timeline.
    let linkedMessage: Message?
    /// The thread's first message for a thread reply also sent to the chat,
    /// resolved from the canonical timeline.
    let threadRoot: Message?

    var id: String { message.timelineKey }

    /// Rows for the optimistic tail, which renders directly after `messages`.
    /// The first outgoing row continues from the last canonical message, so a
    /// send after a long quiet period gets its divider immediately.
    static func entries(for outgoingMessages: [OutgoingMessage], following messages: [Message]) -> [OutgoingTimelineEntry] {
        var previousTimestamp = messages.last?.timestamp
        var followsOtherSender = messages.last.map { !$0.isSender } == true
        return outgoingMessages.map { message in
            let showsTimestamp = TimelineEntry.showsTimestamp(before: message.createdAt, previous: previousTimestamp)
            let startsSenderRun = followsOtherSender && !showsTimestamp
            previousTimestamp = message.createdAt
            followsOtherSender = false
            return OutgoingTimelineEntry(
                message: message,
                showsTimestamp: showsTimestamp,
                startsSenderRun: startsSenderRun,
                linkedMessage: message.replyToMessageID.flatMap { replyID in messages.first { $0.id == replyID } },
                threadRoot: message.broadcastThreadRootID.flatMap { rootID in messages.first { $0.id == rootID } }
            )
        }
    }
}
