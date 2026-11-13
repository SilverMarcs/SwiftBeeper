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
    /// Replies go into threads, as on Slack, which has no quoted replies.
    let threads: Bool?
}

struct ListChatsOutput: Decodable {
    let items: [Chat]
    let hasMore: Bool
    let pinned: [Chat]?
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
    /// False once the server has returned the start of the chat. Until then,
    /// older history may exist beyond the local database.
    let hasServerHistory: Bool
    /// For a page read around a message or after a cursor: where the next
    /// newer page starts, and whether there is one. A page without newer
    /// messages beyond it reaches the newest message.
    let newestCursor: String?
    let hasMoreNewer: Bool?
}

struct GetMessagesOutput: Decodable {
    let items: [Message]
}

/// A thread from the local database: its root and replies, oldest first.
struct ListThreadOutput: Decodable {
    let root: Message?
    let items: [Message]
}

struct LoadServerHistoryOutput: Decodable {
    /// False once the server has returned the start of the chat.
    let hasMore: Bool
}

struct SendMessageOutput: Decodable {
    let chatID: String
    let pendingMessageID: String
    /// The network takes no media captions, so the media went without its
    /// text; send the text on its own after the remaining media.
    let captionRejected: Bool?
}

/// What a chat's info screen shows below its header, from the local database.
struct ChatInfoOutput: Decodable, Equatable {
    let mediaCount: Int
    let fileCount: Int
    let linkCount: Int
    /// Whether the chat's network deletes the chat itself; otherwise deleting
    /// only leaves it here.
    let canDeleteChat: Bool

    func count(of kind: ChatMediaKind) -> Int {
        switch kind {
        case .media: mediaCount
        case .files: fileCount
        case .links: linkCount
        }
    }
}

/// One page of a chat's media, files or links, newest first.
struct ChatMessagePage: Decodable {
    let items: [Message]
    let hasMore: Bool
    /// Continues after this page's oldest row, even on the last page, for
    /// history fetched from the server later. Nil when the page is empty.
    let cursor: String?
    /// Whether older history can still be fetched from the server, where
    /// later pages can find it.
    let hasServerHistory: Bool
}
