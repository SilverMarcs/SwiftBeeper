import Foundation

struct WatchMessagePage: Codable, Sendable {
    let chatID: String
    let updatedAt: Date
    let items: [WatchMessageSummary]
}
