import Foundation

extension APIClient {
    static func listChats(cursor: String? = nil, direction: String? = nil, accessToken: String) async throws -> ListChatsOutput {
        var components = URLComponents(url: API.baseURL.appending(path: "/v1/chats"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let direction { queryItems.append(URLQueryItem(name: "direction", value: direction)) }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw APIError.invalidResponse
        }
        return try await get(url: url, accessToken: accessToken)
    }

    static func listLowPriorityChatIDs(accessToken: String) async throws -> Set<String> {
        var components = URLComponents(url: API.baseURL.appending(path: "/v1/chats/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "inbox", value: "low-priority")]
        guard let url = components.url else {
            throw APIError.invalidResponse
        }
        let response: SearchChatsOutput = try await get(url: url, accessToken: accessToken)
        return Set(response.items.map(\.id))
    }

    static func searchChats(query: String? = nil, inbox: String? = nil, cursor: String? = nil, direction: String? = nil, accessToken: String) async throws -> SearchChatsOutput {
        var components = URLComponents(url: API.baseURL.appending(path: "/v1/chats/search"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        if let query { queryItems.append(URLQueryItem(name: "query", value: query)) }
        if let inbox { queryItems.append(URLQueryItem(name: "inbox", value: inbox)) }
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let direction { queryItems.append(URLQueryItem(name: "direction", value: direction)) }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw APIError.invalidResponse
        }
        return try await get(url: url, accessToken: accessToken)
    }

    static func getChat(chatID: String, accessToken: String) async throws -> Chat {
        var components = URLComponents(url: API.baseURL.appending(path: "/v1/chats/\(chatID)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "maxParticipantCount", value: "-1")]
        guard let url = components.url else {
            throw APIError.invalidResponse
        }
        return try await get(url: url, accessToken: accessToken)
    }

    static func archiveChat(chatID: String, archived: Bool, accessToken: String) async throws {
        guard let url = URL(string: "/v1/chats/\(chatID)/archive", relativeTo: API.baseURL) else {
            throw APIError.invalidResponse
        }

        try await postNoContent(
            url: url,
            body: ArchiveChatRequest(archived: archived),
            accessToken: accessToken
        )
    }
}

private struct ArchiveChatRequest: Encodable {
    let archived: Bool
}
