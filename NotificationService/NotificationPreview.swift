import Foundation

struct NotificationPreview: Decodable, Sendable {
    let title: String
    let body: String
    let senderID: String
    let senderName: String
    let isGroup: Bool
    let avatar: Data?
    let recipients: [NotificationParticipant]?
}
