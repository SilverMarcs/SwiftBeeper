import Foundation

extension APIClient {
    /// One page of chats, newest first, starting after `before` when given.
    static func listChats(inbox: String, accountIDs: [String], before: Chat? = nil) async throws -> ListChatsOutput {
        try await execute("list-chats", arguments: ChatListArguments(
            query: nil,
            inbox: inbox,
            accountIDs: accountIDs,
            beforeTS: before?.lastActivity.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) },
            beforeRoomID: before?.id
        ))
    }

    static func searchChats(query: String, inbox: String, accountIDs: [String]) async throws -> SearchChatsOutput {
        try await execute("search-chats", arguments: ChatListArguments(
            query: query, inbox: inbox, accountIDs: accountIDs, beforeTS: nil, beforeRoomID: nil
        ))
    }

    static func getChat(chatID: String, maxParticipantCount: Int = 5) async throws -> Chat {
        struct Arguments: Encodable { let chatID: String; let maxParticipantCount: Int }
        return try await execute("get-chat", arguments: Arguments(chatID: chatID, maxParticipantCount: maxParticipantCount))
    }

    static func archiveChat(chatID: String, archived: Bool) async throws {
        struct Arguments: Encodable { let chatID: String; let archived: Bool }
        try await executeRaw("archive-chat", arguments: Arguments(chatID: chatID, archived: archived))
    }

    static func muteChat(chatID: String, muted: Bool) async throws {
        struct Arguments: Encodable { let chatID: String; let muted: Bool }
        try await executeRaw("mute-chat", arguments: Arguments(chatID: chatID, muted: muted))
    }

    static func markChatAsRead(chatID: String) async throws {
        struct Arguments: Encodable { let chatID: String }
        try await executeRaw("mark-chat-read", arguments: Arguments(chatID: chatID))
    }

    static func getSession() async throws -> SessionOutput {
        try await execute("session", arguments: EmptyArguments())
    }
}

private struct ChatListArguments: Encodable {
    let query: String?
    let inbox: String
    let accountIDs: [String]
    let beforeTS: Int64?
    let beforeRoomID: String?
}
