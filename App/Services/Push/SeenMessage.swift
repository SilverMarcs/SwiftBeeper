import Foundation

/// An incoming message the user has already seen on screen, as the push
/// server records it so a later push for it sends nothing.
nonisolated struct SeenMessage: Encodable, Hashable, Sendable {
    let chatID: String
    let messageID: String
}
