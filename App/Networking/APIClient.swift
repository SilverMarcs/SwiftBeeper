import Foundation

enum APIClient {
    private static let _tokenLock = NSLock()
    private static var _accessToken: String = ""

    static var accessToken: String {
        get { _tokenLock.withLock { _accessToken } }
        set { _tokenLock.withLock { _accessToken = newValue } }
    }

    static func execute<Arguments: Encodable, Response: Decodable>(
        _ action: String, arguments: Arguments
    ) async throws -> Response {
        let data = try await executeRaw(action, arguments: arguments)
        do {
            return try JSONDecoder.beeper.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    @discardableResult
    static func executeRaw<Arguments: Encodable>(_ action: String, arguments: Arguments) async throws -> Data {
        let input = try JSONEncoder.beeper.encode(MatrixCommand(action: action, arguments: arguments))
        return try await MatrixRuntime.shared.command(input)
    }
}

struct EmptyArguments: Encodable {}

enum APIError: LocalizedError {
    case operation(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .operation(let message):
            if message.contains("context deadline exceeded") {
                return "The connection timed out. Please try again."
            }
            return message
        case .decoding(let details):
            return "Failed to decode Matrix core response: \(details)"
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
