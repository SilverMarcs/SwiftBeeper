import Foundation

/// Typed actions of the in-process Matrix core. Arguments are encoded here,
/// on the caller's actor, and the JSON is handed to `MatrixRuntime`.
enum APIClient {
    static func execute<Arguments: Encodable, Response: Decodable>(
        _ action: String, arguments: Arguments
    ) async throws -> Response {
        let data = try await executeRaw(action, arguments: arguments)
        do {
            return try JSONDecoder.beeper.decode(Response.self, from: data)
        } catch {
            throw MatrixError.decoding(error.localizedDescription)
        }
    }

    @discardableResult
    static func executeRaw<Arguments: Encodable>(_ action: String, arguments: Arguments) async throws -> Data {
        let input = try JSONEncoder().encode(MatrixCommand(action: action, arguments: arguments))
        return try await MatrixRuntime.shared.command(input)
    }
}

extension JSONDecoder {
    /// Decodes core results, whose dates are ISO 8601 strings.
    static let beeper: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
