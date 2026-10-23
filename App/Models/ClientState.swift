import Foundation

struct ClientState: Decodable {
    let isLoggedIn: Bool
    let isVerified: Bool

    enum CodingKeys: String, CodingKey {
        case isLoggedIn = "is_logged_in"
        case isVerified = "is_verified"
    }
}
