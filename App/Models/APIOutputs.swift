import Foundation

struct ListChatsOutput: Decodable {
    let items: [Chat]
    let hasMore: Bool
}

struct SearchChatsOutput: Decodable {
    let items: [Chat]
}

struct ListMessagesOutput: Decodable {
    let items: [Message]
    let hasMore: Bool
    let oldestCursor: String?
    /// The sortKey of the furthest message that at least one other participant has read.
    /// Outgoing messages with sortKey <= this value have been seen by the other side.
    let lastReadByOtherSortKey: String?
}

struct SendMessageOutput: Decodable {
    let chatID: String
    let pendingMessageID: String
}

struct Account: Decodable, Identifiable, Equatable {
    let accountID: String
    let user: ChatParticipant
    let network: String
    let capabilities: AccountCapabilities

    var id: String { accountID }
}

struct AccountCapabilities: Decodable, Equatable {
    let unlimitedMessageEdits: Bool
}

struct SessionOutput: Decodable, Equatable {
    let user: ChatParticipant
    let accounts: [Account]
}
