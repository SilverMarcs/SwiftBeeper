import Foundation

struct WatchMessageSummary: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let senderName: String
    let text: String
    let timestamp: Date
    let isOutgoing: Bool
}
