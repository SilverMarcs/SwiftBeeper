import Foundation

/// Commands behind the chat info screen. Counts and lists read only the
/// local database.
extension APIClient {
    static func getChatInfo(chatID: String) async throws -> ChatInfoOutput {
        try await execute("get-chat-info", arguments: ChatArguments(chatID: chatID))
    }

    /// One page of the chat's photos and videos, files, or links, newest first.
    static func listChatMedia(chatID: String, kind: ChatMediaKind, cursor: String?) async throws -> ChatMessagePage {
        struct Arguments: Encodable { let chatID: String; let kind: String; let cursor: String? }
        return try await execute("list-chat-media", arguments: Arguments(chatID: chatID, kind: kind.rawValue, cursor: cursor))
    }

    /// Group chats shared with a participant, on the source chat's account.
    static func listCommonChats(participantID: String, sourceChatID: String) async throws -> [Chat] {
        struct Arguments: Encodable { let participantID: String; let sourceChatID: String }
        return try await execute("list-common-chats", arguments: Arguments(
            participantID: participantID, sourceChatID: sourceChatID
        ))
    }

    /// Deletes the chat on its network when it supports that; otherwise
    /// leaves it.
    static func deleteChat(chatID: String) async throws {
        try await executeRaw("delete-chat", arguments: ChatArguments(chatID: chatID))
    }

    static func leaveChat(chatID: String) async throws {
        try await executeRaw("leave-chat", arguments: ChatArguments(chatID: chatID))
    }

    private struct ChatArguments: Encodable { let chatID: String }
}
