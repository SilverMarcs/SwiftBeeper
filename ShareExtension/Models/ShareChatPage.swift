import Foundation

/// A `list-chats` or `search-chats` result. Only the first unfiltered page
/// carries pinned chats.
struct ShareChatPage: Decodable {
    let items: [ShareChat]
    let pinned: [ShareChat]?
}
