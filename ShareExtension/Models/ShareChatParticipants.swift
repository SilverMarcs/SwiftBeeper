import Foundation

/// A chat's first few members, as the core lists them.
struct ShareChatParticipants: Hashable, Decodable {
    let items: [ShareChatParticipant]
}
