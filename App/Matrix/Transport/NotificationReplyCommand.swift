import Foundation

struct NotificationReplyCommand: Encodable {
    let action = "notification-reply"
    let roomID: String
    let eventID: String?
    let text: String
}
