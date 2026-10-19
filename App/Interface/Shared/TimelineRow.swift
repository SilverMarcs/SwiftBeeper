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

    var timestamp: Date { message?.timestamp ?? outgoing?.createdAt ?? .distantPast }
    var text: String { message?.visibleText ?? outgoing?.text ?? "" }

    static func make(store: ChatStore, chat: Chat, firstUnreadID: String?) -> [Self] {
        let messages = store.messages(for: chat.id)
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
                showsAvatar: !sameNext || next?.id == firstUnreadID, isUnreadBoundary: message.id == firstUnreadID))
        }
        var previousDate = messages.last?.timestamp
        for outgoing in store.outgoingMessages(for: chat.id) {
            rows.append(Self(id: outgoing.timelineKey, message: nil, outgoing: outgoing,
                linkedMessage: outgoing.replyToMessageID.flatMap { byID[$0] },
                showsTimestamp: showsTimestamp(outgoing.createdAt, after: previousDate),
                showsSender: false, showsAvatar: false, isUnreadBoundary: false))
            previousDate = outgoing.createdAt
        }
        return rows
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
