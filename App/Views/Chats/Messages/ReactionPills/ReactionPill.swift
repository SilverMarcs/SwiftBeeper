import Foundation

/// One reaction key on one message, drawn as a pill below the message's bubbles.
struct ReactionPill: Identifiable, Equatable {
    var id: String { "\(message.id)-\(group.reactionKey)" }
    let message: Message
    let group: GroupedReaction
    /// Whether the user is among those who reacted with it.
    let isOwn: Bool

    /// What the pill shows: which reaction, how many reacted, and whether the
    /// user did. The pills animate when these change, and not when anything
    /// else about their message does.
    var displayKey: String { "\(id) \(group.count) \(isOwn)" }

    /// Pills shown before the rest fold into an overflow pill.
    static let visibleLimit = 4

    /// Every message's reactions, each message's most reacted first. A gallery
    /// passes all its photos and caption; each keeps its own reactions.
    static func pills(for messages: [Message], selfIDs: Set<String>) -> [ReactionPill] {
        messages.flatMap { message in
            message.groupedReactions.map { group in
                ReactionPill(
                    message: message,
                    group: group,
                    isOwn: group.participantIDs.contains(where: selfIDs.contains)
                )
            }
        }
    }
}
