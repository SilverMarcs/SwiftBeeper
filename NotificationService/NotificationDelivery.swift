import Synchronization
import UserNotifications

/// Apple may expire the request while decryption is finishing. Complete once.
final class NotificationDelivery: Sendable {
    // The handler and mutable content move together under the mutex and are
    // handed to exactly one finisher; neither is accessed by another thread.
    private struct State: @unchecked Sendable {
        var content: UNMutableNotificationContent?
        var handler: ((UNNotificationContent) -> Void)?
    }

    private let state = Mutex(State())

    func begin(content: UNMutableNotificationContent, handler: @escaping (UNNotificationContent) -> Void) {
        let ownedContent = content.mutableCopy() as? UNMutableNotificationContent
        state.withLock { $0 = State(content: ownedContent, handler: handler) }
    }

    /// Save decrypted text before the optional Siri donation can time out.
    func prepare(_ preview: NotificationPreview) -> UNNotificationContent? {
        state.withLock { value in
            guard let content = value.content else { return nil }
            let isMention = preview.mentionsMe == true || content.userInfo["isMention"] as? Bool == true
            content.title = preview.title
            content.subtitle = preview.subtitle(isMention: isMention)
            content.body = preview.body
            content.userInfo["isMention"] = isMention
            if let targetEventID = preview.targetEventID {
                content.userInfo["messageID"] = targetEventID
            }
            return content.copy() as? UNNotificationContent
        }
    }

    func finish(content updatedContent: UNNotificationContent? = nil) {
        let pending = state.withLock { value -> State in
            let pending = value
            value = State()
            return pending
        }
        guard let content = pending.content, let handler = pending.handler else { return }
        handler(updatedContent ?? content)
    }
}
