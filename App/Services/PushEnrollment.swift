import CryptoKit
import Foundation

/// Compare successful enrollment without persisting the APNs token or secret.
nonisolated struct PushEnrollment: Codable, Equatable {
    let tokenDigest: String
    let userID: String
    let deviceID: String
    let gateway: String
    let secretDigest: String

    init(token: String, identity: PushIdentity, configuration: PushConfiguration) {
        tokenDigest = Self.digest(token)
        userID = identity.userID
        deviceID = identity.deviceID
        gateway = configuration.serverURL.absoluteString
        secretDigest = Self.digest(configuration.registrationSecret)
    }

    private static func digest(_ value: String) -> String {
        Data(SHA256.hash(data: Data(value.utf8))).base64EncodedString()
    }
}
