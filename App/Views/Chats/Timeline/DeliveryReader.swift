import Foundation

/// Someone who has seen a group message: who, to find their avatar, and
/// their name in the chat, for initials and the caption's spoken label when
/// the chat hasn't loaded them as a participant.
struct DeliveryReader: Identifiable, Equatable, Sendable {
    /// Their Matrix user ID.
    let id: String
    let name: String
}
