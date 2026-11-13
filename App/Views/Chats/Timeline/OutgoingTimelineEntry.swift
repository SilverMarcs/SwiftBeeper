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
    /// Matches `TimelineEntry.bubbleJoins`, so the confirmed row keeps the
    /// shape this one's bubbles had.
    let bubbleJoins: MessageBubbleJoins
    /// The quoted message for a reply, resolved from the canonical timeline.
    let linkedMessage: Message?
    /// The thread's first message for a thread reply also sent to the chat,
    /// resolved from the canonical timeline.
    let threadRoot: Message?

    var id: String { message.timelineKey }

    /// Rows for the optimistic tail, which renders directly after `messages`.
    /// The first outgoing row continues from the last canonical message, so a
    /// send after a long quiet period gets its divider immediately.
    /// `joinsLastRow` is whether that message's row carries on into the first
    /// optimistic one (its `bubbleJoins` contains `.below`).
    static func entries(
        for outgoingMessages: [OutgoingMessage],
        following messages: [Message],
        joinsLastRow: Bool = false,
        isThread: Bool = false
    ) -> [OutgoingTimelineEntry] {
        var previousTimestamp = messages.last?.timestamp
        var followsOtherSender = messages.last.map { !$0.isSender } == true
        let rows = outgoingMessages.indices.map { index in
            let message = outgoingMessages[index]
            let showsTimestamp = TimelineEntry.showsTimestamp(before: message.createdAt, previous: previousTimestamp)
            let startsSenderRun = followsOtherSender && !showsTimestamp
            previousTimestamp = message.createdAt
            followsOtherSender = false
            let joinsAbove = index == 0
                ? joinsLastRow
                : !showsTimestamp && !message.breaksBubbleRunAbove(isThread: isThread)
                    && !outgoingMessages[index - 1].breaksBubbleRunBelow
            return (message: message, showsTimestamp: showsTimestamp, startsSenderRun: startsSenderRun, joinsAbove: joinsAbove)
        }
        return rows.indices.map { index in
            let row = rows[index]
            let message = row.message
            return OutgoingTimelineEntry(
                message: message,
                showsTimestamp: row.showsTimestamp,
                startsSenderRun: row.startsSenderRun,
                // A typing bubble after the last one starts its own group.
                bubbleJoins: MessageBubbleJoins(above: row.joinsAbove, below: index < rows.endIndex - 1 && rows[index + 1].joinsAbove),
                linkedMessage: message.replyToMessageID.flatMap { replyID in messages.first { $0.id == replyID } },
                threadRoot: message.broadcastThreadRootID.flatMap { rootID in messages.first { $0.id == rootID } }
            )
        }
    }

    /// Whether the first optimistic row carries on the bubbles of the newest
    /// canonical message, as it will once confirmed: both the user's, with no
    /// divider, quote or label between them. The canonical row's own
    /// reactions and captions below it are `TimelineEntry`'s to weigh.
    static func continuesBubbles(of messages: [Message], into outgoingMessages: [OutgoingMessage], isThread: Bool) -> Bool {
        guard let last = messages.last, last.isSender, let first = outgoingMessages.first else { return false }
        return !TimelineEntry.showsTimestamp(before: first.createdAt, previous: last.timestamp)
            && !first.breaksBubbleRunAbove(isThread: isThread)
    }
}
