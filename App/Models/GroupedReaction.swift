import Foundation

struct GroupedReaction: Identifiable {
    var id: String { reactionKey }
    let reactionKey: String
    var count: Int
    var participantIDs: [String]
}
