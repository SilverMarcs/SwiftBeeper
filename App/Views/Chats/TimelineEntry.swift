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

    /// Groups consecutive messages from one sender. A timestamp break or the
    /// unread divider starts a new group.
    static func entries(
        for messages: [Message],
        firstUnreadID: String?,
        lastReadByOtherSortKey: String?
    ) -> [TimelineEntry] {
        let messagesByID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let readIndicatorID = readIndicatorMessageID(in: messages, lastReadByOtherSortKey: lastReadByOtherSortKey)

        return messages.indices.map { index in
            let message = messages[index]
            let previous = index > messages.startIndex ? messages[index - 1] : nil
            let next = index < messages.endIndex - 1 ? messages[index + 1] : nil

            let showsTimestamp = TimelineTimestampRule.showsDivider(before: message.timestamp, previous: previous?.timestamp)
            let nextShowsTimestamp = next.map {
                TimelineTimestampRule.showsDivider(before: $0.timestamp, previous: message.timestamp)
            } ?? false

            return TimelineEntry(
                message: message,
                showsTimestamp: showsTimestamp,
                isFirstInGroup: previous?.senderID != message.senderID || showsTimestamp || message.id == firstUnreadID,
                isLastInGroup: next?.senderID != message.senderID || nextShowsTimestamp || next?.id == firstUnreadID,
                showsReadIndicator: message.id == readIndicatorID,
                linkedMessage: message.linkedMessageID.flatMap { messagesByID[$0] }
            )
        }
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
