import Foundation

/// Intentional mention recipients, independent of links in the displayed text.
struct MessageMentions: Codable, Equatable, Sendable {
    let userIDs: [String]
    let room: Bool
}
