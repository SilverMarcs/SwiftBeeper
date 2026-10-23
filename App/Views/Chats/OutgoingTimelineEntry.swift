import Foundation

/// Grouping decisions for an optimistic (not yet server-confirmed) row, computed
/// with the same rules the canonical timeline uses so the bubble doesn't visibly
/// re-group when the server's version replaces it.
struct OutgoingTimelineEntry: Identifiable, Equatable {
    let message: OutgoingMessage
    let showsTimestamp: Bool
    /// The quoted message for a reply, resolved from the canonical timeline.
    let linkedMessage: Message?

    var id: String { message.timelineKey }

    /// Rows for the optimistic tail, which renders directly after `messages`.
    /// The first outgoing row continues from the last canonical message, so a
    /// send after a long quiet period gets its divider immediately.
    static func entries(for outgoingMessages: [OutgoingMessage], following messages: [Message]) -> [OutgoingTimelineEntry] {
        var previousTimestamp = messages.last?.timestamp
        return outgoingMessages.map { message in
            let showsTimestamp = TimelineTimestampRule.showsDivider(before: message.createdAt, previous: previousTimestamp)
            previousTimestamp = message.createdAt
            return OutgoingTimelineEntry(
                message: message,
                showsTimestamp: showsTimestamp,
                linkedMessage: message.replyToMessageID.flatMap { replyID in messages.first { $0.id == replyID } }
            )
        }
    }
}
