import Foundation

extension APIClient {
    static func listChats(
        inbox: String? = nil,
        accountIDs: [String] = [],
        cursor: String? = nil,
        direction: String? = nil
    ) async throws -> ListChatsOutput {
        var components = URLComponents(url: APIConfiguration.baseURL.appending(path: "/v1/chats"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        if let inbox { queryItems.append(URLQueryItem(name: "inbox", value: inbox)) }
        queryItems.append(contentsOf: accountIDs.map { URLQueryItem(name: "accountIDs", value: $0) })
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let direction { queryItems.append(URLQueryItem(name: "direction", value: direction)) }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw APIError.invalidURL("/v1/chats")
        }
        return try await get(url: url)
    }



    static func searchChats(
        query: String? = nil,
        inbox: String? = nil,
        accountIDs: [String] = [],
        cursor: String? = nil,
        direction: String? = nil
    ) async throws -> SearchChatsOutput {
        var components = URLComponents(url: APIConfiguration.baseURL.appending(path: "/v1/chats/search"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        if let query { queryItems.append(URLQueryItem(name: "query", value: query)) }
        if let inbox { queryItems.append(URLQueryItem(name: "inbox", value: inbox)) }
        queryItems.append(contentsOf: accountIDs.map { URLQueryItem(name: "accountIDs", value: $0) })
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let direction { queryItems.append(URLQueryItem(name: "direction", value: direction)) }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw APIError.invalidURL("/v1/chats/search")
        }
        return try await get(url: url)
    }

    static func getChat(chatID: String, maxParticipantCount: Int = 5) async throws -> Chat {
        var components = URLComponents(url: APIConfiguration.baseURL.appending(path: "/v1/chats/\(chatID)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "maxParticipantCount", value: String(maxParticipantCount))]
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

    static func muteChat(chatID: String, muted: Bool) async throws {
        guard let url = URL(string: "/v1/chats/\(chatID)/mute", relativeTo: APIConfiguration.baseURL) else {
            throw APIError.invalidURL("/v1/chats/\(chatID)/mute")
        }

        let _: ActionSuccessOutput = try await post(
            url: url,
            body: MuteChatRequest(muted: muted)
        )
    }

    static func markChatAsRead(chatID: String) async throws {
        guard let url = URL(string: "/v1/chats/\(chatID)/read", relativeTo: APIConfiguration.baseURL) else {
            throw APIError.invalidURL("/v1/chats/\(chatID)/read")
        }

        let _: ActionSuccessOutput = try await post(
            url: url,
            body: EmptyBody()
        )
    }

    static func getSession() async throws -> SessionOutput {
        guard let url = URL(string: "/v1/session", relativeTo: APIConfiguration.baseURL) else {
            throw APIError.invalidURL("/v1/session")
        }
        return try await get(url: url)
    }
}

private struct ArchiveChatRequest: Encodable {
    let archived: Bool
}

private struct MuteChatRequest: Encodable {
    let muted: Bool
}

private struct EmptyBody: Encodable {}

private struct ActionSuccessOutput: Decodable {
    let success: Bool
}
