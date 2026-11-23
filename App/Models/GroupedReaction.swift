import Foundation

/// Everyone who reacted to a message with one reaction key, in the order they
/// reacted. Reactions Relay can't draw are grouped together instead.
struct GroupedReaction: Identifiable, Equatable {
    let appearance: ReactionAppearance
    /// A custom emoji's name, such as ":party_parrot:".
    let shortcode: String?
    var participantIDs: [String]

    var id: String { appearance.id }
    var count: Int { participantIDs.count }

    /// How VoiceOver and captions name the reaction.
    var spokenName: String {
        guard appearance == .unrecognized else { return appearance.spokenName(shortcode: shortcode) }
        return count == 1 ? "Unrecognized reaction" : "Unrecognized reactions"
    }
}
