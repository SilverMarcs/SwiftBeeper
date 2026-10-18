import Foundation

nonisolated struct MatrixPusherCommand: Encodable {
    let action: String
    let pushkey: String
    let appID: String
    let gatewayURL: String?
    let deviceDisplayName: String?
}
