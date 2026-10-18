import Foundation

nonisolated struct MatrixConfiguration: Codable, Sendable {
    let stateDir: String
    let accessToken: String
    let manageSecret: String
    let beeperHomeserverUrl: String
}
