import Foundation

struct WatchChatPage: Codable, Sendable {
    let updatedAt: Date
    let items: [WatchChatSummary]
}
