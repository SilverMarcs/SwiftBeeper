import Foundation

/// The last derived message rows of a timeline. `ChatTimelineView`'s body also
/// runs for typing, the outbox, loading state and the composer, and rebuilding
/// every row from all loaded messages each time grows with history; this hands
/// back the previous rows while their inputs are unchanged.
final class TimelineEntriesCache {
    private struct RowInputs: Equatable {
        /// The messages array's storage. The cache keeps the array, so the
        /// store can't mutate that storage in place: a change means new storage.
        let messagesStorage: UnsafeRawPointer?
        let messageCount: Int
        let firstUnreadID: String?
        let followingTypingSenderID: String?
        let isThread: Bool
        let followingRowContinues: Bool
    }

    /// Receipt changes update captions independently. Rows only need rebuilding
    /// when that caption changes whether the newest bubble joins the typing row.
    private struct CaptionInputs: Equatable {
        let messagesStorage: UnsafeRawPointer?
        let messageCount: Int
        let readReceipts: [ReadReceipt]
        let groupMemberCount: Int?
    }

    private var rowInputs: RowInputs?
    private var captionInputs: CaptionInputs?
    private var messages: [Message] = []
    private var quotedMessages: [Message.ID: Message] = [:]
    private var entries: [TimelineEntry] = []
    /// The caption below the user's newest message, from the same inputs as
    /// the rows.
    private(set) var deliveryCaption: DeliveryCaption?
    /// Who has seen the newest message in a group, when someone else sent it.
    private(set) var newestSeenCaption: DeliveryIndicator?

    /// The rows for `messages`. `continuesIntoOutgoing` says whether the
    /// first optimistic row carries on the newest row's bubbles.
    func entries(
        for messages: [Message],
        firstUnreadID: String?,
        readReceipts: [ReadReceipt],
        groupMemberCount: Int?,
        quotedMessages: [Message.ID: Message],
        followingTypingSenderID: String?,
        isThread: Bool = false,
        continuesIntoOutgoing: Bool = false
    ) -> [TimelineEntry] {
        let storage = messages.withUnsafeBufferPointer { UnsafeRawPointer($0.baseAddress) }
        let captionInputs = CaptionInputs(
            messagesStorage: storage,
            messageCount: messages.count,
            readReceipts: readReceipts,
            groupMemberCount: groupMemberCount
        )
        if captionInputs != self.captionInputs {
            newestSeenCaption = TimelineEntry.newestSeenCaption(
                in: messages,
                readReceipts: readReceipts,
                groupMemberCount: groupMemberCount
            )
            deliveryCaption = TimelineEntry.deliveryCaption(
                in: messages,
                readReceipts: readReceipts,
                groupMemberCount: groupMemberCount
            )
            self.captionInputs = captionInputs
        }
        // The newest row's sender typing again carries on its bubbles,
        // unless the caption of who has seen it sits between them.
        let typingContinues = followingTypingSenderID != nil
            && followingTypingSenderID == messages.last?.senderID
            && newestSeenCaption == nil
        let rowInputs = RowInputs(
            messagesStorage: storage,
            messageCount: messages.count,
            firstUnreadID: firstUnreadID,
            followingTypingSenderID: followingTypingSenderID,
            isThread: isThread,
            followingRowContinues: continuesIntoOutgoing || typingContinues
        )
        if rowInputs == self.rowInputs, quotedMessages == self.quotedMessages {
            return entries
        }
        entries = TimelineEntry.entries(
            for: messages,
            firstUnreadID: firstUnreadID,
            quotedMessages: quotedMessages,
            followingTypingSenderID: followingTypingSenderID,
            isThread: isThread,
            followingRowContinues: rowInputs.followingRowContinues
        )
        self.rowInputs = rowInputs
        self.messages = messages
        self.quotedMessages = quotedMessages
        return entries
    }
}
