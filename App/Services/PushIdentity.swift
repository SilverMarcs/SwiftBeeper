import Foundation

nonisolated struct PushIdentity: Decodable {
    let userID: String
    let deviceID: String
    let backupKey: String
}
