import Foundation

struct ManageState: Decodable {
    private let clientState: ClientState?

    var isLoggedIn: Bool { clientState?.isLoggedIn == true }
    /// Whether the session can decrypt; until then sign-in asks for the recovery key.
    var isVerified: Bool { clientState?.isVerified == true }

    private enum CodingKeys: String, CodingKey {
        case clientState = "client_state"
    }

    private struct ClientState: Decodable {
        let isLoggedIn: Bool
        let isVerified: Bool

        enum CodingKeys: String, CodingKey {
            case isLoggedIn = "is_logged_in"
            case isVerified = "is_verified"
        }
    }
}

struct SessionOutput: Decodable, Equatable {
    let user: ChatParticipant
    let accounts: [Account]
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

struct UploadAssetOutput: Decodable {
    let uploadID: String
    let width: Int?
    let height: Int?
}
