import Foundation

struct ListChatsOutput: Decodable {
    let items: [Chat]
    let hasMore: Bool?
    let oldestCursor: String?
    let newestCursor: String?
}

struct SearchChatsOutput: Decodable {
    let items: [Chat]
    let hasMore: Bool
    let oldestCursor: String?
    let newestCursor: String?
}

struct ListMessagesOutput: Decodable {
    let items: [Message]
    let hasMore: Bool
    /// The sortKey of the furthest message that at least one other participant has read.
    /// Outgoing messages with sortKey <= this value have been seen by the other side.
    let lastReadByOtherSortKey: String?
}

struct SendMessageOutput: Decodable {
    let chatID: String
    let pendingMessageID: String
}

struct EditMessageOutput: Decodable {
    let chatID: String
    let messageID: String
    let success: Bool
}

struct AddReactionOutput: Decodable {
    let success: Bool
    let chatID: String
    let messageID: String
    let reactionKey: String
    let transactionID: String
}

struct RemoveReactionOutput: Decodable {
    let success: Bool
    let chatID: String
    let messageID: String
    let reactionKey: String
}

struct Account: Decodable, Identifiable, Equatable, Hashable {
    let accountID: String
    let network: String?

    var id: String { accountID }
}

