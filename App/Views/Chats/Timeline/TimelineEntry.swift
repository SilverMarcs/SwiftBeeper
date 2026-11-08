import Foundation

/// A canonical message plus the grouping decisions the timeline renders around it.
/// Equatable so SwiftUI skips rows whose entry didn't change.
struct TimelineEntry: Identifiable, Equatable {
    let message: Message
    /// Photos sent right after `message` that share its gallery bubble.
    /// Empty unless `message` starts a run of two or more photos.
    let galleryMessages: [Message]
    let showsTimestamp: Bool
    let isFirstInGroup: Bool
    let isLastInGroup: Bool
    /// Whether the sender changed from the row directly above, with no divider
    /// between them. The timeline widens the gap there to separate the two sides.
    let startsSenderRun: Bool
    /// Whether this is the outgoing message that shows the "Read" indicator.
    let showsReadIndicator: Bool
    /// The message this one replies to, from the timeline or, when older,
    /// the source's quoted-message lookup.
    let linkedMessage: Message?

    var id: String { message.id }

    /// Every message this row renders, in timeline order.
    var messages: [Message] { [message] + galleryMessages }

    /// Gap after which the timeline breaks into a new time-stamped section.
    static let timestampGap: TimeInterval = 30 * 60

    /// The divider rule shared with the optimistic tail, so the two can't drift apart.
    static func showsTimestamp(before timestamp: Date, previous: Date?) -> Bool {
        guard let previous else { return true }
        if !Calendar.app.isDate(timestamp, inSameDayAs: previous) { return true }
        return timestamp.timeIntervalSince(previous) >= timestampGap
    }

    /// Groups consecutive messages from one sender. A timestamp break or the
    /// unread divider starts a new group. Runs of photos fold into one row.
    static func entries(
        for messages: [Message],
        firstUnreadID: String?,
        lastReadByOtherSortKey: String?,
        quotedMessages: [Message.ID: Message] = [:],
        followingTypingSenderID: String? = nil
    ) -> [TimelineEntry] {
        let messagesByID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let readIndicatorID = readIndicatorMessageID(in: messages, lastReadByOtherSortKey: lastReadByOtherSortKey)
        let rows = galleryRows(in: messages, firstUnreadID: firstUnreadID)

        return rows.indices.map { index in
            let row = rows[index]
            let message = row[0]
            let lastMessage = row[row.count - 1]
            let previous = index > rows.startIndex ? rows[index - 1].last : nil
            let next = index < rows.endIndex - 1 ? rows[index + 1].first : nil

            let showsTimestamp = Self.showsTimestamp(before: message.timestamp, previous: previous?.timestamp)
            let nextShowsTimestamp = next.map {
                Self.showsTimestamp(before: $0.timestamp, previous: lastMessage.timestamp)
            } ?? false

            return TimelineEntry(
                message: message,
                galleryMessages: Array(row.dropFirst()),
                showsTimestamp: showsTimestamp,
                isFirstInGroup: previous?.senderID != message.senderID || showsTimestamp || message.id == firstUnreadID,
                isLastInGroup: (next?.senderID ?? followingTypingSenderID) != message.senderID
                    || nextShowsTimestamp || (next.map { $0.id == firstUnreadID } ?? false),
                startsSenderRun: previous.map { $0.senderID != message.senderID } == true
                    && !showsTimestamp && message.id != firstUnreadID,
                showsReadIndicator: row.contains { $0.id == readIndicatorID },
                linkedMessage: message.linkedMessageID.flatMap { messagesByID[$0] ?? quotedMessages[$0] }
            )
        }
    }

    /// The row a message renders in: itself, or the gallery it was folded into.
    static func rowID(for messageID: Message.ID, in entries: [TimelineEntry]) -> Message.ID {
        entries.first { entry in entry.galleryMessages.contains { $0.id == messageID } }?.id ?? messageID
    }

    /// Splits the timeline into rows, folding photo runs together. The unread
    /// divider sits above a row, so it always starts a new one.
    private static func galleryRows(in messages: [Message], firstUnreadID: String?) -> [[Message]] {
        var rows: [[Message]] = []
        for message in messages {
            if let previous = rows.last?.last, message.id != firstUnreadID, message.continuesGallery(after: previous) {
                rows[rows.count - 1].append(message)
            } else {
                rows.append([message])
            }
        }
        return rows
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
