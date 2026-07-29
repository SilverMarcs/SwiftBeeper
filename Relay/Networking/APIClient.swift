import Foundation

enum APIClient {
    private static let _tokenLock = NSLock()
    private static var _accessToken: String = ""

    static var accessToken: String {
        get { _tokenLock.withLock { _accessToken } }
        set { _tokenLock.withLock { _accessToken = newValue } }
    }

    static func clearToken() {
        accessToken = ""
    }

    static func makeWebSocketTask() -> URLSessionWebSocketTask {
        let request = request(url: APIConfiguration.webSocketURL, method: .get, accessToken: Self.accessToken)
        return URLSession.shared.webSocketTask(with: request)
    }

    static func get<Response: Decodable>(url: URL) async throws -> Response {
        let request = request(url: url, method: .get, accessToken: Self.accessToken)
        return try await send(request)
    }

    static func post<Body: Encodable, Response: Decodable>(
        url: URL,
        body: Body
    ) async throws -> Response {
        let request = try request(url: url, method: .post, body: body, accessToken: Self.accessToken)
        return try await send(request)
    }

    static func put<Body: Encodable, Response: Decodable>(
        url: URL,
        body: Body
    ) async throws -> Response {
        let request = try request(url: url, method: .put, body: body, accessToken: Self.accessToken)
        return try await send(request)
    }

    static func delete<Response: Decodable>(url: URL) async throws -> Response {
        let request = request(url: url, method: .delete, accessToken: Self.accessToken)
        return try await send(request)
    }

    static func postNoContent<Body: Encodable>(
        url: URL,
        body: Body
    ) async throws {
        let request = try request(url: url, method: .post, body: body, accessToken: Self.accessToken)
        _ = try await sendRaw(request)
    }

    static func parseErrorMessage(from data: Data) -> String? {
        guard let payload = try? JSONDecoder.beeper.decode(APIErrorPayload.self, from: data) else {
            return nil
        }
        return payload.message
    }

    static func request(url: URL, method: HTTPMethod, accessToken: String) -> URLRequest {
        // The backend is in-process on localhost, so healthy requests return
        // in well under a second. Cap the wait far below URLSession's 60 s
        // default so that a request caught mid-rebind (e.g. connecting just as
        // iOS reaps the socket on foreground) fails fast and lets the caller
        // retry, instead of leaving a tap hanging for a minute.
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if url.path.hasPrefix("/manage/") || url.path == "/manage" {
            let manageSecret = APIConfiguration.manageSecret
            if !manageSecret.isEmpty {
                request.setValue(manageSecret, forHTTPHeaderField: "X-EasyMatrix-Manage-Secret")
            }
        }
        return request
    }

    /// Wired up by the app at startup. Returns a fresh bearer token. Called
    /// at most once per request when sendRaw observes a 401 on a /v1/* path,
    /// then the request is retried with the new token.
    static var tokenRefresher: (() async throws -> String)?

    static func request<Body: Encodable>(
        url: URL,
        method: HTTPMethod,
        body: Body,
        accessToken: String
    ) throws -> URLRequest {
        var request = request(url: url, method: method, accessToken: accessToken)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.beeper.encode(body)
        return request
    }

    static func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data = try await sendRaw(request)

        do {
            return try JSONDecoder.beeper.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    @discardableResult
    static func sendRaw(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401,
           request.url?.path.hasPrefix("/v1/") == true,
           let refresher = tokenRefresher {
            do {
                let newToken = try await refresher()
                var retry = request
                retry.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                let (retryData, retryResponse) = try await URLSession.shared.data(for: retry)
                guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                    throw APIError.invalidResponse
                }
                guard (200 ... 299).contains(retryHTTP.statusCode) else {
                    throw APIError.http(statusCode: retryHTTP.statusCode, details: parseErrorMessage(from: retryData))
                }
                return retryData
            } catch {
                // refresh failed — fall through and surface the original 401
            }
        }

        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw APIError.http(statusCode: httpResponse.statusCode, details: parseErrorMessage(from: data))
        }

        return data
    }
}

private struct APIErrorPayload: Decodable {
    let message: String
}

enum APIError: LocalizedError {
    case invalidURL(String)
    case invalidResponse
    case http(statusCode: Int, details: String?)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let urlString):
            return "Invalid URL: \(urlString)"
        case .invalidResponse:
            return "Invalid server response."
        case .http(let statusCode, let details):
            if let details, !details.isEmpty {
                return "Request failed (\(statusCode)): \(details)"
            }
            return "Request failed with status code \(statusCode)."
        case .decoding(let details):
            return "Failed to decode server response: \(details)"
        }
    }
}

extension JSONDecoder {
    static let beeper: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension JSONEncoder {
    static let beeper = JSONEncoder()
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}
