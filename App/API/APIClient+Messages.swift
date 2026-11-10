import Foundation

extension APIClient {
    static func resolveMedia(chatID: String, messageID: String) async throws {
        try await executeRaw("resolve-media", arguments: MessageArguments(chatID: chatID, messageID: messageID))
    }

    /// The newest page of messages, or the page older than `cursor`.
    static func listMessages(chatID: String, cursor: String? = nil) async throws -> ListMessagesOutput {
        struct Arguments: Encodable { let chatID: String; let cursor: String? }
        return try await execute("list-messages", arguments: Arguments(chatID: chatID, cursor: cursor))
    }

    /// Fetches older history from the server into the local database, where
    /// `listMessages` pages it.
    static func loadServerHistory(chatID: String) async throws -> LoadServerHistoryOutput {
        struct Arguments: Encodable { let chatID: String }
        return try await execute("load-server-history", arguments: Arguments(chatID: chatID))
    }

    /// Sends a message, in `threadRootID`'s thread when given. `alsoSendToChat`
    /// shows a thread reply in the main timeline too. `afterPendingMessageID`
    /// holds it until that earlier part of the same send reaches the server.
    static func sendMessage(
        chatID: String,
        text: String?,
        replyToMessageID: String? = nil,
        threadRootID: String? = nil,
        alsoSendToChat: Bool = false,
        attachment: MessageAttachmentInput? = nil,
        mentions: [ComposerMention] = [],
        afterPendingMessageID: String? = nil
    ) async throws -> SendMessageOutput {
        struct Arguments: Encodable {
            let chatID: String
            let text: String?
            let replyToMessageID: String?
            let threadRootID: String?
            let alsoSendToChat: Bool
            let attachment: MessageAttachmentInput?
            let mentions: [ComposerMention]
            let afterPendingMessageID: String?
        }
        return try await execute("send-message", arguments: Arguments(
            chatID: chatID, text: text, replyToMessageID: replyToMessageID, threadRootID: threadRootID,
            alsoSendToChat: alsoSendToChat, attachment: attachment, mentions: mentions,
            afterPendingMessageID: afterPendingMessageID
        ))
    }

    /// Specific messages from the local database, such as quoted messages
    /// older than the loaded timeline. IDs it doesn't store are absent.
    static func getMessages(chatID: String, messageIDs: [String]) async throws -> [Message] {
        struct Arguments: Encodable { let chatID: String; let messageIDs: [String] }
        let output: GetMessagesOutput = try await execute("get-messages", arguments: Arguments(chatID: chatID, messageIDs: messageIDs))
        return output.items
    }

    /// A thread's root and replies from the local database.
    static func listThread(chatID: String, threadRootID: String) async throws -> ListThreadOutput {
        try await execute("list-thread", arguments: ThreadArguments(chatID: chatID, threadRootID: threadRootID))
    }

    /// Fetches a thread's root and replies from the server into the local
    /// database, where `listThread` reads them.
    static func loadThreadHistory(chatID: String, threadRootID: String) async throws {
        try await executeRaw("load-thread-history", arguments: ThreadArguments(chatID: chatID, threadRootID: threadRootID))
    }

    static func editMessage(chatID: String, messageID: String, text: String, mentions: [ComposerMention] = []) async throws {
        struct Arguments: Encodable {
            let chatID: String
            let messageID: String
            let text: String
            let mentions: [ComposerMention]
        }
        try await executeRaw("edit-message", arguments: Arguments(chatID: chatID, messageID: messageID, text: text, mentions: mentions))
    }

    static func addReaction(chatID: String, messageID: String, reactionKey: String) async throws {
        try await executeRaw("add-reaction", arguments: ReactionArguments(chatID: chatID, messageID: messageID, reactionKey: reactionKey))
    }

    static func removeReaction(chatID: String, messageID: String, reactionKey: String) async throws {
        try await executeRaw("remove-reaction", arguments: ReactionArguments(chatID: chatID, messageID: messageID, reactionKey: reactionKey))
    }

    static func deleteMessage(chatID: String, messageID: String) async throws {
        try await executeRaw("delete-message", arguments: MessageArguments(chatID: chatID, messageID: messageID))
    }
}

private struct ThreadArguments: Encodable {
    let chatID: String
    let threadRootID: String
}

private struct MessageArguments: Encodable {
    let chatID: String
    let messageID: String
}

private struct ReactionArguments: Encodable {
    let chatID: String
    let messageID: String
    let reactionKey: String
}
