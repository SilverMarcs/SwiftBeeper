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
