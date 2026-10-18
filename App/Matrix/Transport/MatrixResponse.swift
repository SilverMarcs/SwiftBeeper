import Foundation

nonisolated struct MatrixResponse: Decodable, Sendable {
    let response: Body?
    struct Body: Decodable, Sendable {
        let status: Int
        let headers: [String: [String]]?
        let bodyBase64: String?
        enum CodingKeys: String, CodingKey { case status, headers; case bodyBase64 = "body_base64" }
    }
}
