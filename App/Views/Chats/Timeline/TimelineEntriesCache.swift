import Foundation

/// The last derived message rows of a timeline. `ChatTimelineView`'s body also
/// runs for typing, the outbox, loading state and the composer, and rebuilding
/// every row from all loaded messages each time grows with history; this hands
/// back the previous rows while their inputs are unchanged.
final class TimelineEntriesCache {
    private struct Inputs: Equatable {
        /// The messages array's storage. The cache keeps the array, so the
        /// store can't mutate that storage in place: a change means new storage.
        let messagesStorage: UnsafeRawPointer?
        let messageCount: Int
        let firstUnreadID: String?
        let lastReadByOtherSortKey: String?
        let followingTypingSenderID: String?
    }

    private var inputs: Inputs?
    private var messages: [Message] = []
    private var quotedMessages: [Message.ID: Message] = [:]
    private var entries: [TimelineEntry] = []
    /// The caption for the newest message, from the same inputs as the rows.
    private(set) var deliveryIndicator: DeliveryIndicator?

    func entries(
        for messages: [Message],
        firstUnreadID: String?,
        lastReadByOtherSortKey: String?,
        quotedMessages: [Message.ID: Message],
        followingTypingSenderID: String?
    ) -> [TimelineEntry] {
        let inputs = Inputs(
            messagesStorage: messages.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) },
            messageCount: messages.count,
            firstUnreadID: firstUnreadID,
            lastReadByOtherSortKey: lastReadByOtherSortKey,
            followingTypingSenderID: followingTypingSenderID
        )
        if inputs == self.inputs, quotedMessages == self.quotedMessages {
            return entries
        }
        entries = TimelineEntry.entries(
            for: messages,
            firstUnreadID: firstUnreadID,
            lastReadByOtherSortKey: lastReadByOtherSortKey,
            quotedMessages: quotedMessages,
            followingTypingSenderID: followingTypingSenderID
        )
        deliveryIndicator = TimelineEntry.deliveryIndicator(in: messages, lastReadByOtherSortKey: lastReadByOtherSortKey)
        self.inputs = inputs
        self.messages = messages
        self.quotedMessages = quotedMessages
        return entries
    }
}
