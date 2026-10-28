import Foundation

/// A decrypted push, as `RelayNotificationPreview` returns it.
struct NotificationPreview: Decodable, Sendable {
    struct Participant: Decodable, Sendable {
        let id: String
        let name: String
    }

    let title: String
    let body: String
    let senderID: String
    let senderName: String
    let isGroup: Bool
    let avatar: Data?
    let recipients: [Participant]?
    let targetEventID: String?
    let mentionsMe: Bool?

    var subtitle: String {
        if mentionsMe == true {
            return isGroup ? String(localized: "\(senderName) mentioned you") : String(localized: "Mentioned you")
        }
        return isGroup ? senderName : ""
    }
}
