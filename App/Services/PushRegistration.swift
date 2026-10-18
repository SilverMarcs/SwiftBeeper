import Foundation

nonisolated struct PushRegistration: Codable {
    let pushkey: String
    let appID: String

    enum CodingKeys: String, CodingKey {
        case pushkey
        case appID = "app_id"
    }
}
