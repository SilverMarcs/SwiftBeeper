import Foundation

/// How far another participant has read a chat.
struct ReadReceipt: Codable, Equatable, Sendable {
    let userID: String
    /// Their name in the chat.
    let name: String
    /// The furthest message they have read.
    let sortKey: String

    var numericSortKey: Int64 { Int64(sortKey) ?? 0 }
}
