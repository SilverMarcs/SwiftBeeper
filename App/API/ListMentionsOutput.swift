import Foundation

/// One page of unread personal mentions, oldest first. The captured read
/// position stays fixed while the reader works through the queue.
struct ListMentionsOutput: Decodable {
    let items: [Message]
    let after: String
    let hasMore: Bool
}
