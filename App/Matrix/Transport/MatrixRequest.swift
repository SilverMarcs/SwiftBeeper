import Foundation

nonisolated struct MatrixRequest: Encodable, Sendable {
    let method: String
    let url: String
    let headers: [String: [String]]
    let bodyBase64: String?
    enum CodingKeys: String, CodingKey { case method, url, headers; case bodyBase64 = "body_base64" }
}
