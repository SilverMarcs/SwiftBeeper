import Foundation

/// The replies a thread root shows under its bubble, like Slack's "3 replies".
struct ThreadSummary: Codable, Equatable, Sendable {
    let replyCount: Int
    /// The most recent repliers first.
    let participants: [ChatParticipant]?
}
