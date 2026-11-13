import Foundation

/// Everyone who reacted to a message with one reaction key, in the order they reacted.
struct GroupedReaction: Identifiable, Equatable {
    var id: String { reactionKey }
    let reactionKey: String
    var participantIDs: [String]

    var count: Int { participantIDs.count }
}
