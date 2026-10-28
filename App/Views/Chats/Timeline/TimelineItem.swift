import Foundation

/// One identity space lets an incoming message take over its typing row.
enum TimelineItem: Identifiable {
    case message(TimelineEntry, rowID: String)
    case outgoing(OutgoingTimelineEntry)
    case typing(TypingBubble, isFirstInGroup: Bool)

    var id: String {
        switch self {
        case .message(_, let rowID): rowID
        case .outgoing(let entry): entry.id
        case .typing(let bubble, _): bubble.id
        }
    }

    var hasTypingIdentity: Bool {
        switch self {
        case .message(let entry, let rowID): rowID != entry.id
        case .typing: true
        case .outgoing: false
        }
    }

    static func items(
        messages: [TimelineEntry],
        outgoing: [OutgoingTimelineEntry],
        typing: TypingBubble?,
        messageRowIDs: [Message.ID: String]
    ) -> [TimelineItem] {
        var items = messages.map { entry in
            TimelineItem.message(entry, rowID: messageRowIDs[entry.id] ?? entry.id)
        }
        items += outgoing.map { .outgoing($0) }
        if let typing {
            let isFirstInGroup = !outgoing.isEmpty || messages.last?.message.senderID != typing.participant.id
            items.append(.typing(typing, isFirstInGroup: isFirstInGroup))
        }
        return items
    }
}
