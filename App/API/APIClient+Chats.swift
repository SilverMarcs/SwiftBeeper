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

    /// Looks up an existing DM in the local database, on the source chat's account.
    static func findDirectChat(participantID: String, sourceChatID: String) async throws -> Chat? {
        struct Arguments: Encodable { let participantID: String; let sourceChatID: String }
        return try await execute("find-direct-chat", arguments: Arguments(
            participantID: participantID, sourceChatID: sourceChatID
        ))
    }

    static func archiveChat(chatID: String, archived: Bool) async throws {
        struct Arguments: Encodable { let chatID: String; let archived: Bool }
        try await executeRaw("archive-chat", arguments: Arguments(chatID: chatID, archived: archived))
    }

    static func muteChat(chatID: String, muted: Bool) async throws -> Chat {
        struct Arguments: Encodable { let chatID: String; let muted: Bool }
        return try await execute("mute-chat", arguments: Arguments(chatID: chatID, muted: muted))
    }

    static func pinChat(chatID: String, pinned: Bool) async throws {
        struct Arguments: Encodable { let chatID: String; let pinned: Bool }
        try await executeRaw("pin-chat", arguments: Arguments(chatID: chatID, pinned: pinned))
    }

    static func markChatAsRead(chatID: String) async throws {
        struct Arguments: Encodable { let chatID: String }
        try await executeRaw("mark-chat-read", arguments: Arguments(chatID: chatID))
    }

    static func markChatAsUnread(chatID: String) async throws -> Chat {
        struct Arguments: Encodable { let chatID: String }
        return try await execute("mark-chat-unread", arguments: Arguments(chatID: chatID))
    }
}

/// Shared by listing and search; a page cursor is the last chat's activity and ID.
private struct ChatListArguments: Encodable {
    let query: String?
    let inbox: String
    let accountIDs: [String]
    let beforeTS: Int64?
    let beforeRoomID: String?
}
