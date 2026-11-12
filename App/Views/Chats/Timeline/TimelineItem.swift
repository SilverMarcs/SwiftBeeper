import Foundation

/// One identity space lets an incoming message take over its typing row.
enum TimelineItem: Identifiable {
    case message(TimelineEntry, rowID: String)
    case outgoing(OutgoingTimelineEntry)
    /// "Sending…" through "Read", below the newest row when the user sent it.
    case deliveryCaption(DeliveryIndicator)
    case typing(TypingBubble, isFirstInGroup: Bool)

    var id: String {
        switch self {
        case .message(_, let rowID): rowID
        case .outgoing(let entry): entry.id
        // One identity for every step and every message, so a step replaces
        // the last in place, even across an optimistic row's confirmation.
        case .deliveryCaption: "delivery-caption"
        case .typing(let bubble, _): bubble.id
        }
    }

    /// The ID `scrollTo` reaches this row by. Typing and caption rows aren't
    /// scroll targets.
    var scrollTargetID: String? {
        switch self {
        case .message(let entry, _): entry.message.id
        case .outgoing(let entry): entry.id
        case .deliveryCaption, .typing: nil
        }
    }

    var isDeliveryCaption: Bool {
        if case .deliveryCaption = self { true } else { false }
    }

    var hasTypingIdentity: Bool {
        switch self {
        case .message(let entry, let rowID): rowID != entry.id
        case .typing: true
        case .outgoing, .deliveryCaption: false
        }
    }

    static func items(
        messages: [TimelineEntry],
        outgoing: [OutgoingTimelineEntry],
        deliveryCaption: DeliveryIndicator?,
        typing: TypingBubble?,
        messageRowIDs: [Message.ID: String]
    ) -> [TimelineItem] {
        var items = messages.map { entry in
            TimelineItem.message(entry, rowID: messageRowIDs[entry.id] ?? entry.id)
        }
        items += outgoing.map { .outgoing($0) }
        if let deliveryCaption {
            items.append(.deliveryCaption(deliveryCaption))
        }
        if let typing {
            let isFirstInGroup = !outgoing.isEmpty || messages.last?.message.senderID != typing.participant.id
            items.append(.typing(typing, isFirstInGroup: isFirstInGroup))
        }
        return items
    }
}
