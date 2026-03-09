import Foundation
import OSLog

enum APIClient {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SwiftBeeper", category: "APIClient")

    static func makeWebSocketTask(accessToken: String) -> URLSessionWebSocketTask {
        let request = request(url: APIConfiguration.webSocketURL, method: .get, accessToken: accessToken)
        return URLSession.shared.webSocketTask(with: request)
    }

    static func get<Response: Decodable>(url: URL, accessToken: String) async throws -> Response {
        let request = request(url: url, method: .get, accessToken: accessToken)
        return try await send(request)
    }

    static func post<Body: Encodable, Response: Decodable>(
        url: URL,
        body: Body,
        accessToken: String
    ) async throws -> Response {
        let request = try request(url: url, method: .post, body: body, accessToken: accessToken)
        return try await send(request)
    }

    static func put<Body: Encodable, Response: Decodable>(
        url: URL,
        body: Body,
        accessToken: String
    ) async throws -> Response {
        let request = try request(url: url, method: .put, body: body, accessToken: accessToken)
        return try await send(request)
    }

    static func delete<Response: Decodable>(url: URL, accessToken: String) async throws -> Response {
        let request = request(url: url, method: .delete, accessToken: accessToken)
        return try await send(request)
    }

    static func postNoContent<Body: Encodable>(
        url: URL,
        body: Body,
        accessToken: String
    ) async throws {
        let request = try request(url: url, method: .post, body: body, accessToken: accessToken)
        _ = try await sendRaw(request)
    }

    static func parseErrorMessage(from data: Data) -> String? {
        guard let payload = try? JSONDecoder.beeper.decode(APIErrorPayload.self, from: data) else {
            return nil
        }
        return payload.message
    }

    static func request(url: URL, method: HTTPMethod, accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

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
            logger.error("Decoding failed for \(request.httpMethod ?? "UNKNOWN", privacy: .public) \(request.url?.absoluteString ?? "<nil>", privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw APIError.decoding(error.localizedDescription)
        }
    }

    @discardableResult
    static func sendRaw(_ request: URLRequest) async throws -> Data {
        logger.debug("Sending \(request.httpMethod ?? "UNKNOWN", privacy: .public) \(request.url?.absoluteString ?? "<nil>", privacy: .public)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        logger.debug("Received \(httpResponse.statusCode, privacy: .public) for \(request.url?.absoluteString ?? "<nil>", privacy: .public)")

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
    case invalidResponse
    case http(statusCode: Int, details: String?)
    case decoding(String)

    var errorDescription: String? {
        switch self {
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
    static var beeper: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    static var beeper: JSONEncoder {
        JSONEncoder()
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}
