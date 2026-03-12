import Foundation

extension APIClient {
    static func listChats(cursor: String? = nil, direction: String? = nil) async throws -> ListChatsOutput {
        var components = URLComponents(url: APIConfiguration.baseURL.appending(path: "/v1/chats"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let direction { queryItems.append(URLQueryItem(name: "direction", value: direction)) }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw APIError.invalidURL("/v1/chats")
        }
        return try await get(url: url)
    }

    static func listLowPriorityChatIDs() async throws -> Set<String> {
        var components = URLComponents(url: APIConfiguration.baseURL.appending(path: "/v1/chats/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "inbox", value: "low-priority")]
        guard let url = components.url else {
            throw APIError.invalidURL("/v1/chats/search")
        }
        let response: ChatIDsOutput = try await get(url: url)
        return Set(response.items.map(\.id))
    }

    static func searchChats(query: String? = nil, inbox: String? = nil, cursor: String? = nil, direction: String? = nil) async throws -> SearchChatsOutput {
        var components = URLComponents(url: APIConfiguration.baseURL.appending(path: "/v1/chats/search"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        if let query { queryItems.append(URLQueryItem(name: "query", value: query)) }
        if let inbox { queryItems.append(URLQueryItem(name: "inbox", value: inbox)) }
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let direction { queryItems.append(URLQueryItem(name: "direction", value: direction)) }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw APIError.invalidURL("/v1/chats/search")
        }
        return try await get(url: url)
    }

    static func getChat(chatID: String) async throws -> Chat {
        var components = URLComponents(url: APIConfiguration.baseURL.appending(path: "/v1/chats/\(chatID)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "maxParticipantCount", value: "-1")]
        guard let url = components.url else {
            throw APIError.invalidURL("/v1/chats/\(chatID)")
        }
        return try await get(url: url)
    }

    static func archiveChat(chatID: String, archived: Bool) async throws {
        guard let url = URL(string: "/v1/chats/\(chatID)/archive", relativeTo: APIConfiguration.baseURL) else {
            throw APIError.invalidURL("/v1/chats/\(chatID)/archive")
        }

        try await postNoContent(
            url: url,
            body: ArchiveChatRequest(archived: archived)
        )
    }
}

private struct ArchiveChatRequest: Encodable {
    let archived: Bool
}

private struct ChatIDOnly: Decodable {
    let id: String
}

private struct ChatIDsOutput: Decodable {
    let items: [ChatIDOnly]
}
