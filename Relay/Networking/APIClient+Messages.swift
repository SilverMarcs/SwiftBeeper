import Foundation

extension APIClient {
    static func listMessages(chatID: String, cursor: String? = nil, direction: String? = nil) async throws -> ListMessagesOutput {
        var components = URLComponents(url: APIConfiguration.baseURL.appending(path: "/v1/chats/\(chatID)/messages"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let direction { queryItems.append(URLQueryItem(name: "direction", value: direction)) }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw APIError.invalidURL("/v1/chats/\(chatID)/messages")
        }
        return try await get(url: url)
    }

    static func sendMessage(chatID: String, text: String?, replyToMessageID: String? = nil, attachment: MessageAttachmentInput? = nil) async throws -> SendMessageOutput {
        guard let url = URL(string: "/v1/chats/\(chatID)/messages", relativeTo: APIConfiguration.baseURL) else {
            throw APIError.invalidURL("/v1/chats/\(chatID)/messages")
        }

        return try await post(
            url: url,
            body: SendMessageRequest(text: text, replyToMessageID: replyToMessageID, attachment: attachment)
        )
    }

    static func editMessage(chatID: String, messageID: String, text: String) async throws -> EditMessageOutput {
        guard let url = URL(string: "/v1/chats/\(chatID)/messages/\(messageID)", relativeTo: APIConfiguration.baseURL) else {
            throw APIError.invalidURL("/v1/chats/\(chatID)/messages/\(messageID)")
        }

        return try await put(
            url: url,
            body: EditMessageRequest(text: text)
        )
    }

    static func addReaction(chatID: String, messageID: String, reactionKey: String) async throws -> AddReactionOutput {
        guard let url = URL(string: "/v1/chats/\(chatID)/messages/\(messageID)/reactions", relativeTo: APIConfiguration.baseURL) else {
            throw APIError.invalidURL("/v1/chats/\(chatID)/messages/\(messageID)/reactions")
        }

        return try await post(
            url: url,
            body: AddReactionRequest(reactionKey: reactionKey)
        )
    }

    static func removeReaction(chatID: String, messageID: String, reactionKey: String) async throws -> RemoveReactionOutput {
        var components = URLComponents(url: APIConfiguration.baseURL.appending(path: "/v1/chats/\(chatID)/messages/\(messageID)/reactions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "reactionKey", value: reactionKey)]
        guard let url = components.url else {
            throw APIError.invalidURL("/v1/chats/\(chatID)/messages/\(messageID)/reactions")
        }

        return try await delete(url: url)
    }
}

private struct SendMessageRequest: Encodable {
    let text: String?
    let replyToMessageID: String?
    let attachment: MessageAttachmentInput?
}

private struct EditMessageRequest: Encodable {
    let text: String
}

private struct AddReactionRequest: Encodable {
    let reactionKey: String
}
