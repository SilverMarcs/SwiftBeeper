import Foundation

/// One identity space lets an incoming message take over its typing row.
enum TimelineItem: Identifiable {
    case message(TimelineEntry, rowID: String)
    case outgoing(OutgoingTimelineEntry)
    /// "Sending…" through "Seen", below the newest row when the user sent
    /// it, or in a group who has seen the user's newest message.
    case deliveryCaption(DeliveryIndicator)
    /// In a group, who has seen the newest message when someone else sent it.
    case seenCaption(DeliveryIndicator)
    case typing(TypingBubble, isFirstInGroup: Bool)

    var id: String {
        switch self {
        case .message(_, let rowID): rowID
        case .outgoing(let entry): entry.id
        // One identity for every step and every message, so a step replaces
        // the last in place, even across an optimistic row's confirmation.
        case .deliveryCaption: "delivery-caption"
        case .seenCaption: "seen-caption"
        case .typing(let bubble, _): bubble.id
        }
    }

    /// The ID `scrollTo` reaches this row by. Typing and caption rows aren't
    /// scroll targets.
    var scrollTargetID: String? {
        switch self {
        case .message(let entry, _): entry.message.id
        case .outgoing(let entry): entry.id
        case .deliveryCaption, .seenCaption, .typing: nil
        }
    }

    var isDeliveryCaption: Bool {
        switch self {
        case .deliveryCaption, .seenCaption: true
        case .message, .outgoing, .typing: false
        }
    }

    var hasTypingIdentity: Bool {
        switch self {
        case .message(let entry, let rowID): rowID != entry.id
        case .typing: true
        case .outgoing, .deliveryCaption, .seenCaption: false
        }
    }

    static func items(
        messages: [TimelineEntry],
        outgoing: [OutgoingTimelineEntry],
        deliveryCaption: DeliveryIndicator?,
        deliveryCaptionRowID: Message.ID?,
        seenCaption: DeliveryIndicator?,
        typing: TypingBubble?,
        messageRowIDs: [Message.ID: String]
    ) -> [TimelineItem] {
        var items = messages.map { entry in
            TimelineItem.message(entry, rowID: messageRowIDs[entry.id] ?? entry.id)
        }
        if let seenCaption {
            // Below the newest message, ahead of any optimistic rows.
            items.append(.seenCaption(seenCaption))
        }
        items += outgoing.map { .outgoing($0) }
        if let deliveryCaption {
            // Below its message's row, or else below the newest.
            let rowIndex = deliveryCaptionRowID.flatMap { rowID in
                messages.firstIndex { $0.id == rowID }
            }
            items.insert(.deliveryCaption(deliveryCaption), at: rowIndex.map { $0 + 1 } ?? items.endIndex)
        }
        if let typing {
            let isFirstInGroup = !outgoing.isEmpty || messages.last?.message.senderID != typing.participant.id
            items.append(.typing(typing, isFirstInGroup: isFirstInGroup))
        }
        return items
    }
}
