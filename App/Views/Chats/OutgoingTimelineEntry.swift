import Foundation

/// Grouping decisions for an optimistic (not yet server-confirmed) row, computed
/// with the same rules the canonical timeline uses so the bubble doesn't visibly
/// re-group when the server's version replaces it.
struct OutgoingTimelineEntry: Identifiable {
    let message: OutgoingMessage
    let showsTimestamp: Bool
    /// The quoted message for a reply, resolved from the canonical timeline.
    let linkedMessage: Message?

    var id: String { message.timelineKey }
}

/// Shared timeline divider rules, so the optimistic tail and the canonical
/// timeline can't drift apart.
enum TimelineTimestampRule {
    /// Gap after which the timeline breaks into a new time-stamped section.
    static let gap: TimeInterval = 30 * 60

    static func showsDivider(before timestamp: Date, previous: Date?) -> Bool {
        guard let previous else { return true }

        let calendar = Calendar.app
        if calendar.isDate(timestamp, inSameDayAs: previous) == false {
            return true
        }

        return timestamp.timeIntervalSince(previous) >= gap
    }

    /// Rows for the optimistic tail, which renders directly after `messages`.
    /// The first outgoing row continues from the last canonical message, so a send
    /// that follows a long quiet period gets its divider immediately instead of
    /// only once the server echo lands.
    static func outgoingEntries(
        for outgoingMessages: [OutgoingMessage],
        following messages: [Message]
    ) -> [OutgoingTimelineEntry] {
        guard !outgoingMessages.isEmpty else { return [] }

        // Only pay for the lookup table when something actually quotes a message.
        let messagesByID: [String: Message]
        if outgoingMessages.contains(where: { $0.replyToMessageID?.isEmpty == false }) {
            messagesByID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        } else {
            messagesByID = [:]
        }

        var entries: [OutgoingTimelineEntry] = []
        entries.reserveCapacity(outgoingMessages.count)
        var previousTimestamp = messages.last?.timestamp

        for message in outgoingMessages {
            let showsTimestamp = showsDivider(before: message.createdAt, previous: previousTimestamp)
            let linkedMessage = message.replyToMessageID.flatMap { $0.isEmpty ? nil : messagesByID[$0] }
            entries.append(
                OutgoingTimelineEntry(
                    message: message,
                    showsTimestamp: showsTimestamp,
                    linkedMessage: linkedMessage
                )
            )
            previousTimestamp = message.createdAt
        }

        return entries
    }
}

/// Memoization key for the optimistic tail: it depends on the canonical timeline
/// (the store's O(1) version counter plus which messages are suppressed, since
/// that changes what the last canonical message is) and on the outgoing rows
/// themselves. Every other outgoing field (upload progress) is irrelevant here.
struct OutgoingTimelineKey: Equatable {
    let version: Int
    let suppressingOutgoingIDs: [OutgoingMessage.ID]
    let outgoingKeys: [String]
}
