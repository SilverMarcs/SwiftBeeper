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

    func finish(preview: NotificationPreview? = nil) {
        let pending = state.withLock { value -> State in
            let pending = value
            value = State()
            return pending
        }
        guard let content = pending.content, let handler = pending.handler else { return }
        if let preview {
            content.title = preview.title
            content.body = preview.body
        }
        handler(content)
    }
}
