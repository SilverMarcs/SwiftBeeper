import Foundation

/// A canonical message plus the grouping decisions the timeline renders around it.
/// Equatable so SwiftUI skips rows whose entry didn't change.
struct TimelineEntry: Identifiable, Equatable {
    let message: Message
    /// The rest of a gallery that `message` starts: its photos and the text
    /// shown as its caption. Empty unless the row folds two or more photos.
    let galleryMessages: [Message]
    let showsTimestamp: Bool
    let isFirstInGroup: Bool
    let isLastInGroup: Bool
    /// Whether the sender changed from the row directly above, with no divider
    /// between them. The timeline widens the gap there to separate the two sides.
    let startsSenderRun: Bool
    /// Which of the rows beside it this row's bubbles carry on into, for the
    /// corners where they meet. Grouping alone isn't enough: a quote or
    /// label above the bubbles, or reactions or a caption below them, sit
    /// between and part them.
    let bubbleJoins: MessageBubbleJoins
    /// The message this one replies to, from the timeline or, when older,
    /// the source's quoted-message lookup.
    let linkedMessage: Message?
    /// For a thread reply also sent to the chat, the thread's first message,
    /// resolved the same way as `linkedMessage`.
    let threadRoot: Message?

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
    /// `followingRowContinues` says whether the row rendered after the last
    /// one, an optimistic send or a typing bubble, carries on its bubbles
    /// with nothing between them. In a thread (`isThread`), rows show their
    /// thread labels differently, which moves what parts their bubbles.
    static func entries(
        for messages: [Message],
        firstUnreadID: String?,
        quotedMessages: [Message.ID: Message] = [:],
        followingTypingSenderID: String? = nil,
        isThread: Bool = false,
        followingRowContinues: Bool = false
    ) -> [TimelineEntry] {
        let messagesByID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let rows = galleryRows(in: messages, firstUnreadID: firstUnreadID)
        let breaksAbove = rows.map { breaksBubbleRunAbove($0, isThread: isThread) }
        let breaksBelow = rows.map { breaksBubbleRunBelow($0, isThread: isThread) }

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

            let isFirstInGroup = previous?.senderID != message.senderID || showsTimestamp || message.id == firstUnreadID
            let isLastInGroup = (next?.senderID ?? followingTypingSenderID) != message.senderID
                || nextShowsTimestamp || (next.map { $0.id == firstUnreadID } ?? false)
            // The row after the last isn't a message here; the caller decides.
            let continuesBelow = next == nil ? followingRowContinues : !isLastInGroup && !breaksAbove[index + 1]

            return TimelineEntry(
                message: message,
                galleryMessages: Array(row.dropFirst()),
                showsTimestamp: showsTimestamp,
                isFirstInGroup: isFirstInGroup,
                isLastInGroup: isLastInGroup,
                startsSenderRun: previous.map { $0.senderID != message.senderID } == true
                    && !showsTimestamp && message.id != firstUnreadID,
                bubbleJoins: MessageBubbleJoins(
                    above: !isFirstInGroup && !breaksAbove[index] && !breaksBelow[index - 1],
                    below: continuesBelow && !breaksBelow[index]
                ),
                linkedMessage: message.linkedMessageID.flatMap { messagesByID[$0] ?? quotedMessages[$0] },
                threadRoot: message.broadcastThreadRootID.flatMap { messagesByID[$0] ?? quotedMessages[$0] }
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
        var run: GalleryRun?
        for message in messages {
            if message.id != firstUnreadID, run?.append(message) == true { continue }
            rows += run?.rows ?? []
            run = GalleryRun(startingWith: message)
        }
        rows += run?.rows ?? []
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

    /// A message on its own, as the quoted-message overlay shows it: with its
    /// sender's name and avatar, outside any run or gallery.
    static func standalone(_ message: Message, linkedMessage: Message?, threadRoot: Message?) -> TimelineEntry {
        TimelineEntry(
            message: message,
            galleryMessages: [],
            showsTimestamp: false,
            isFirstInGroup: true,
            isLastInGroup: true,
            startsSenderRun: false,
            bubbleJoins: [],
            linkedMessage: linkedMessage,
            threadRoot: threadRoot
        )
    }

    /// The caption below the user's newest message. In a direct chat it shows
    /// only when that message is the chat's newest. In a group it says who
    /// has seen the message, wherever it is, and until anyone has, how far a
    /// newest message got. `groupMemberCount` is nil outside groups.
    static func deliveryCaption(
        in messages: [Message],
        readReceipts: [ReadReceipt],
        groupMemberCount: Int?
    ) -> DeliveryCaption? {
        guard let groupMemberCount else {
            let lastRead = readReceipts.map(\.numericSortKey).max()
            guard let newest = messages.last,
                  let indicator = deliveryIndicator(in: messages, lastReadByOther: lastRead) else { return nil }
            return DeliveryCaption(indicator: indicator, messageID: newest.id)
        }
        guard let index = messages.lastIndex(where: \.isSender) else { return nil }
        let message = messages[index]
        guard message.deliveryStatus != .failed else { return nil }

        var readers: [String: ChatParticipant] = [:]
        for receipt in readReceipts where receipt.numericSortKey >= message.numericSortKey {
            readers[receipt.userID] = receipt.participant
        }
        // Writing after the message means having seen it, receipt or not.
        // Servers don't turn that into a receipt for others to see.
        for later in messages[(index + 1)...] where !isBridgeBot(later.senderID) {
            readers[later.senderID] = readers[later.senderID] ?? later.senderProfile
        }
        guard !readers.isEmpty else {
            guard index == messages.endIndex - 1,
                  let indicator = deliveryIndicator(in: messages, lastReadByOther: nil) else { return nil }
            return DeliveryCaption(indicator: indicator, messageID: message.id)
        }
        if groupMemberCount > 1, readers.count >= groupMemberCount - 1 {
            return DeliveryCaption(indicator: .seenByAll, messageID: message.id)
        }
        return DeliveryCaption(indicator: .seenBy(sortedReaders(readers)), messageID: message.id)
    }

    /// In a group whose newest message someone else sent, who else has seen
    /// it: never the user, whose receipts aren't among them, nor its sender.
    /// Nil until anyone has, and outside groups (`groupMemberCount` nil).
    static func newestSeenCaption(
        in messages: [Message],
        readReceipts: [ReadReceipt],
        groupMemberCount: Int?
    ) -> DeliveryIndicator? {
        guard let groupMemberCount, let newest = messages.last, !newest.isSender else { return nil }
        var readers: [String: ChatParticipant] = [:]
        for receipt in readReceipts
        where receipt.numericSortKey >= newest.numericSortKey && receipt.userID != newest.senderID {
            readers[receipt.userID] = receipt.participant
        }
        guard !readers.isEmpty else { return nil }
        // Everyone but the user and the sender.
        if groupMemberCount > 2, readers.count >= groupMemberCount - 2 {
            return .seenByAll
        }
        return .seenBy(sortedReaders(readers))
    }

    /// Readers by first name, as the caption lists them, then by ID so equal
    /// names keep their order between passes.
    private static func sortedReaders(_ readers: [String: ChatParticipant]) -> [ChatParticipant] {
        readers.values
            .map { (reader: $0, firstName: DeliveryIndicator.firstName(of: $0.displayName)) }
            .sorted {
                switch $0.firstName.localizedStandardCompare($1.firstName) {
                case .orderedAscending: true
                case .orderedDescending: false
                case .orderedSame: $0.reader.id < $1.reader.id
                }
            }
            .map(\.reader)
    }

    /// The caption for the newest message, when the user sent it: "Seen" once the
    /// other side's receipt reaches it, otherwise what its bridge reported. A
    /// message the homeserver has but the bridge hasn't reported on yet is
    /// still sending, in a chat whose bridge reports at all; elsewhere, the
    /// homeserver having it is as sent as it gets. A failed message shows its
    /// failure instead, and a reply after it needs no caption.
    private static func deliveryIndicator(in messages: [Message], lastReadByOther: Int64?) -> DeliveryIndicator? {
        guard let newest = messages.last, newest.isSender else { return nil }
        if let lastReadByOther, newest.numericSortKey <= lastReadByOther {
            return .seen
        }
        switch newest.deliveryStatus {
        case .delivered: return .delivered
        case .sent: return .sent
        case .failed: return nil
        case nil:
            let bridgeReports = messages.contains { $0.deliveryStatus != nil }
            return bridgeReports ? .sending : .sent
        }
    }

    /// Bridge bots post notices but don't read; the core leaves them out of
    /// receipts and member counts by the same rule.
    private static func isBridgeBot(_ userID: String) -> Bool {
        userID.dropFirst().prefix { $0 != ":" }.hasSuffix("bot")
    }
}
