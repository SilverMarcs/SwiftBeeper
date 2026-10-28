import Foundation

/// A canonical message plus the grouping decisions the timeline renders around it.
/// Equatable so SwiftUI skips rows whose entry didn't change.
struct TimelineEntry: Identifiable, Equatable {
    let message: Message
    let showsTimestamp: Bool
    let isFirstInGroup: Bool
    let isLastInGroup: Bool
    /// Whether this is the outgoing message that shows the "Read" indicator.
    let showsReadIndicator: Bool
    /// The message this one replies to, when it is loaded.
    let linkedMessage: Message?

    var id: String { message.id }

    /// Gap after which the timeline breaks into a new time-stamped section.
    static let timestampGap: TimeInterval = 30 * 60

    /// The divider rule shared with the optimistic tail, so the two can't drift apart.
    static func showsTimestamp(before timestamp: Date, previous: Date?) -> Bool {
        guard let previous else { return true }
        if !Calendar.app.isDate(timestamp, inSameDayAs: previous) { return true }
        return timestamp.timeIntervalSince(previous) >= timestampGap
    }

    /// Groups consecutive messages from one sender. A timestamp break or the
    /// unread divider starts a new group.
    static func entries(
        for messages: [Message],
        firstUnreadID: String?,
        lastReadByOtherSortKey: String?,
        followingTypingSenderID: String? = nil
    ) -> [TimelineEntry] {
        let messagesByID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let readIndicatorID = readIndicatorMessageID(in: messages, lastReadByOtherSortKey: lastReadByOtherSortKey)

        return messages.indices.map { index in
            let message = messages[index]
            let previous = index > messages.startIndex ? messages[index - 1] : nil
            let next = index < messages.endIndex - 1 ? messages[index + 1] : nil

            let showsTimestamp = Self.showsTimestamp(before: message.timestamp, previous: previous?.timestamp)
            let nextShowsTimestamp = next.map {
                Self.showsTimestamp(before: $0.timestamp, previous: message.timestamp)
            } ?? false

            return TimelineEntry(
                message: message,
                showsTimestamp: showsTimestamp,
                isFirstInGroup: previous?.senderID != message.senderID || showsTimestamp || message.id == firstUnreadID,
                isLastInGroup: (next?.senderID ?? followingTypingSenderID) != message.senderID
                    || nextShowsTimestamp || (next.map { $0.id == firstUnreadID } ?? false),
                showsReadIndicator: message.id == readIndicatorID,
                linkedMessage: message.linkedMessageID.flatMap { messagesByID[$0] }
            )
        }
    }

    /// The message the "New Messages" divider sits above: the first after the
    /// chat's read marker, or the first flagged unread when there is no marker.
    static func firstUnreadMessageID(in messages: [Message], chat: Chat) -> String? {
        guard chat.unreadCount > 0 else { return nil }

        if let lastReadSortKey = chat.lastReadMessageSortKey {
            let lastReadNumeric = Int64(lastReadSortKey) ?? 0
            return messages.first { $0.numericSortKey > lastReadNumeric }?.id
        }

        return messages.first { $0.isUnread == true }?.id
    }

    /// The last outgoing message the other side has read. A reply after it
    /// already proves they read it, so then no message shows the indicator.
    private static func readIndicatorMessageID(in messages: [Message], lastReadByOtherSortKey: String?) -> String? {
        guard let readSortKey = lastReadByOtherSortKey.flatMap({ Int64($0) }) else { return nil }
        for message in messages.reversed() {
            guard message.isSender else { return nil }
            if message.numericSortKey <= readSortKey { return message.id }
        }
        return nil
    }
}
