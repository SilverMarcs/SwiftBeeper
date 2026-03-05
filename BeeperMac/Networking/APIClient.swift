import Foundation

private enum API {
    static let baseURL = URL(string: "http://localhost:23373")!
    static let webSocketURL = URL(string: "ws://localhost:23373/v1/ws")!
}

enum APIClient {
    static func listChats(accessToken: String) async throws -> ListChatsOutput {
        try await get(path: "/v1/chats", accessToken: accessToken)
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

    static func searchChats(query: String? = nil, inbox: String? = nil, accessToken: String) async throws -> SearchChatsOutput {
        var components = URLComponents(url: API.baseURL.appending(path: "/v1/chats/search"), resolvingAgainstBaseURL: false)!
        var queryItems: [URLQueryItem] = []
        if let query { queryItems.append(URLQueryItem(name: "query", value: query)) }
        if let inbox { queryItems.append(URLQueryItem(name: "inbox", value: inbox)) }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw APIError.invalidResponse
        }
        return try await get(url: url, accessToken: accessToken)
    }

    static func listMessages(chatID: String, accessToken: String) async throws -> ListMessagesOutput {
        guard let url = URL(string: "/v1/chats/\(chatID)/messages", relativeTo: API.baseURL) else {
            throw APIError.invalidResponse
        }
        return try await get(url: url, accessToken: accessToken)
    }

    static func sendMessage(chatID: String, text: String, accessToken: String) async throws -> SendMessageOutput {
        guard let url = URL(string: "/v1/chats/\(chatID)/messages", relativeTo: API.baseURL) else {
            throw APIError.invalidResponse
        }

        return try await post(
            url: url,
            body: SendMessageRequest(text: text),
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
