import Foundation

extension APIClient {
    /// The newest page of messages, or the page older than `cursor`.
    static func listMessages(chatID: String, cursor: String? = nil) async throws -> ListMessagesOutput {
        struct Arguments: Encodable { let chatID: String; let cursor: String? }
        return try await execute("list-messages", arguments: Arguments(chatID: chatID, cursor: cursor))
    }

    static func sendMessage(chatID: String, text: String?, replyToMessageID: String? = nil, attachment: MessageAttachmentInput? = nil) async throws -> SendMessageOutput {
        struct Arguments: Encodable {
            let chatID: String
            let text: String?
            let replyToMessageID: String?
            let attachment: MessageAttachmentInput?
        }
        return try await execute("send-message", arguments: Arguments(
            chatID: chatID, text: text, replyToMessageID: replyToMessageID, attachment: attachment
        ))
    }

    static func editMessage(chatID: String, messageID: String, text: String) async throws {
        struct Arguments: Encodable { let chatID: String; let messageID: String; let text: String }
        try await executeRaw("edit-message", arguments: Arguments(chatID: chatID, messageID: messageID, text: text))
    }

    static func addReaction(chatID: String, messageID: String, reactionKey: String) async throws {
        try await executeRaw("add-reaction", arguments: ReactionArguments(chatID: chatID, messageID: messageID, reactionKey: reactionKey))
    }

    static func removeReaction(chatID: String, messageID: String, reactionKey: String) async throws {
        try await executeRaw("remove-reaction", arguments: ReactionArguments(chatID: chatID, messageID: messageID, reactionKey: reactionKey))
    }

    static func deleteMessage(chatID: String, messageID: String) async throws {
        struct Arguments: Encodable { let chatID: String; let messageID: String }
        try await executeRaw("delete-message", arguments: Arguments(chatID: chatID, messageID: messageID))
    }
}

private struct ReactionArguments: Encodable {
    let chatID: String
    let messageID: String
    let reactionKey: String
}
