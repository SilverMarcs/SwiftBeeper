import Foundation

private enum API {
    static let baseURL = URL(string: "http://localhost:23373")!
    static let webSocketURL = URL(string: "ws://localhost:23373/v1/ws")!
}

enum APIClient {
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
        let url = API.baseURL.appending(path: "/v1/chats/\(chatID)")
        return try await get(url: url, accessToken: accessToken)
    }

    static func listMessages(chatID: String, cursor: String? = nil, direction: String? = nil, accessToken: String) async throws -> ListMessagesOutput {
        var components = URLComponents(url: API.baseURL.appending(path: "/v1/chats/\(chatID)/messages"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        if let cursor { queryItems.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let direction { queryItems.append(URLQueryItem(name: "direction", value: direction)) }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw APIError.invalidResponse
        }
        return try await get(url: url, accessToken: accessToken)
    }

    static func sendMessage(chatID: String, text: String, replyToMessageID: String? = nil, accessToken: String) async throws -> SendMessageOutput {
        guard let url = URL(string: "/v1/chats/\(chatID)/messages", relativeTo: API.baseURL) else {
            throw APIError.invalidResponse
        }

        return try await post(
            url: url,
            body: SendMessageRequest(text: text, replyToMessageID: replyToMessageID),
            accessToken: accessToken
        )
    }

    static func editMessage(chatID: String, messageID: String, text: String, accessToken: String) async throws -> EditMessageOutput {
        guard let url = URL(string: "/v1/chats/\(chatID)/messages/\(messageID)", relativeTo: API.baseURL) else {
            throw APIError.invalidResponse
        }

        return try await put(
            url: url,
            body: EditMessageRequest(text: text),
            accessToken: accessToken
        )
    }

    static func addReaction(chatID: String, messageID: String, reactionKey: String, accessToken: String) async throws -> AddReactionOutput {
        guard let url = URL(string: "/v1/chats/\(chatID)/messages/\(messageID)/reactions", relativeTo: API.baseURL) else {
            throw APIError.invalidResponse
        }

        return try await post(
            url: url,
            body: AddReactionRequest(reactionKey: reactionKey),
            accessToken: accessToken
        )
    }

    static func removeReaction(chatID: String, messageID: String, reactionKey: String, accessToken: String) async throws -> RemoveReactionOutput {
        var components = URLComponents(url: API.baseURL.appending(path: "/v1/chats/\(chatID)/messages/\(messageID)/reactions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "reactionKey", value: reactionKey)]
        guard let url = components.url else {
            throw APIError.invalidResponse
        }

        return try await delete(url: url, accessToken: accessToken)
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

    static func makeWebSocketTask(accessToken: String) -> URLSessionWebSocketTask {
        var request = URLRequest(url: API.webSocketURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return URLSession.shared.webSocketTask(with: request)
    }

    private static func get<Response: Decodable>(path: String, accessToken: String) async throws -> Response {
        let url = API.baseURL.appending(path: path)
        return try await get(url: url, accessToken: accessToken)
    }

    private static func get<Response: Decodable>(url: URL, accessToken: String) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw APIError.http(statusCode: httpResponse.statusCode, details: parseErrorMessage(from: data))
        }

        do {
            return try JSONDecoder.beeper.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private static func post<Body: Encodable, Response: Decodable>(
        url: URL,
        body: Body,
        accessToken: String
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw APIError.http(statusCode: httpResponse.statusCode, details: parseErrorMessage(from: data))
        }

        do {
            return try JSONDecoder.beeper.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private static func put<Body: Encodable, Response: Decodable>(
        url: URL,
        body: Body,
        accessToken: String
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw APIError.http(statusCode: httpResponse.statusCode, details: parseErrorMessage(from: data))
        }

        do {
            return try JSONDecoder.beeper.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private static func delete<Response: Decodable>(url: URL, accessToken: String) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw APIError.http(statusCode: httpResponse.statusCode, details: parseErrorMessage(from: data))
        }

        do {
            return try JSONDecoder.beeper.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private static func postNoContent<Body: Encodable>(
        url: URL,
        body: Body,
        accessToken: String
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw APIError.http(statusCode: httpResponse.statusCode, details: parseErrorMessage(from: data))
        }
    }

    private static func parseErrorMessage(from data: Data) -> String? {
        guard let payload = try? JSONDecoder().decode(APIErrorPayload.self, from: data) else {
            return nil
        }
        return payload.message
    }
}

private struct APIErrorPayload: Decodable {
    let message: String
}

private struct SendMessageRequest: Encodable {
    let text: String
    let replyToMessageID: String?
}

private struct EditMessageRequest: Encodable {
    let text: String
}

private struct AddReactionRequest: Encodable {
    let reactionKey: String
}

private struct ArchiveChatRequest: Encodable {
    let archived: Bool
}

enum APIError: LocalizedError {
    case invalidResponse
    case http(statusCode: Int, details: String?)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case .http(let statusCode, let details):
            if let details, details.isEmpty == false {
                return "Request failed (\(statusCode)): \(details)"
            }
            return "Request failed with status code \(statusCode)."
        case .decoding(let details):
            return "Failed to decode server response: \(details)"
        }
    }
}

private extension JSONDecoder {
    static var beeper: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
