import Foundation

/// How far another participant has read a chat.
struct ReadReceipt: Codable, Equatable, Sendable {
    let userID: String
    /// Their profile in the chat, from the member event that names them.
    let participant: ChatParticipant
    /// The furthest message they have read.
    let sortKey: String

    var numericSortKey: Int64 { Int64(sortKey) ?? 0 }
}
