import Foundation

struct TimelineRow: Identifiable, Equatable {
    let id: String
    let message: Message?
    let outgoing: OutgoingMessage?
    let linkedMessage: Message?
    let showsTimestamp: Bool
    let showsSender: Bool
    let showsAvatar: Bool
    let isUnreadBoundary: Bool
    let showsReadIndicator: Bool

    var timestamp: Date { message?.timestamp ?? outgoing?.createdAt ?? .distantPast }
    var text: String { message?.visibleText ?? outgoing?.text ?? "" }

    static func make(store: ChatStore, chat: Chat, firstUnreadID: String?) -> [Self] {
        let messages = store.messages(for: chat.id)
        let readIndicatorID = lastReadOutgoingMessageID(messages: messages, chat: chat, readKey: store.lastReadByOtherSortKey)
        let byID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var rows: [Self] = []
        for (index, message) in messages.enumerated() {
            let previous = index > 0 ? messages[index - 1] : nil
            let next = index + 1 < messages.count ? messages[index + 1] : nil
            let divider = showsTimestamp(message.timestamp, after: previous?.timestamp)
            let sameNext = next?.senderID == message.senderID && !showsTimestamp(next?.timestamp ?? .distantPast, after: message.timestamp)
            rows.append(Self(id: message.timelineKey, message: message, outgoing: nil,
                linkedMessage: message.linkedMessageID.flatMap { byID[$0] }, showsTimestamp: divider,
                showsSender: divider || previous?.senderID != message.senderID || message.id == firstUnreadID,
                showsAvatar: !sameNext || next?.id == firstUnreadID, isUnreadBoundary: message.id == firstUnreadID,
                showsReadIndicator: message.id == readIndicatorID))
        }
        var previousDate = messages.last?.timestamp
        for outgoing in store.outgoingMessages(for: chat.id) {
            rows.append(Self(id: outgoing.timelineKey, message: nil, outgoing: outgoing,
                linkedMessage: outgoing.replyToMessageID.flatMap { byID[$0] },
                showsTimestamp: showsTimestamp(outgoing.createdAt, after: previousDate),
                showsSender: false, showsAvatar: false, isUnreadBoundary: false, showsReadIndicator: false))
            previousDate = outgoing.createdAt
        }
        return rows
    }

    /// Match the previous UI: one receipt at the furthest-read outgoing
    /// message, hidden when a later incoming reply already proves it was read.
    private static func lastReadOutgoingMessageID(messages: [Message], chat: Chat, readKey: String?) -> String? {
        guard let readKey, !readKey.isEmpty else { return nil }
        let readSort = Int64(readKey)
        let target = messages.last { message in
            guard message.isOutgoing(in: chat) else { return false }
            if let readSort, let messageSort = Int64(message.sortKey) { return messageSort <= readSort }
            return message.sortKey <= readKey
        }
        guard let target,
              !messages.contains(where: { !$0.isOutgoing(in: chat) && $0.numericSortKey > target.numericSortKey }) else { return nil }
        return target.id
    }

    static func firstUnreadID(store: ChatStore, chat: Chat) -> String? {
        guard chat.unreadCount > 0 else { return nil }
        let messages = store.messages(for: chat.id)
        if let sortKey = chat.lastReadMessageSortKey, let numeric = Int64(sortKey) {
            return messages.first { $0.numericSortKey > numeric }?.id
        }
        return messages.first { $0.isUnread == true }?.id
    }

    private static func showsTimestamp(_ date: Date, after previous: Date?) -> Bool {
        guard let previous else { return true }
        return !Calendar.app.isDate(date, inSameDayAs: previous) || date.timeIntervalSince(previous) >= 30 * 60
    }
}
