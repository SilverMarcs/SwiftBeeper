import Foundation
@preconcurrency import UserNotifications

final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNNotificationContent?
    private var hasDelivered = false

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        lock.withLock {
            self.contentHandler = contentHandler
            bestAttemptContent = request.content
            hasDelivered = false
        }

        Task { [weak self] in
            guard let self else { return }
            let information = CommunicationNotificationInfo(
                userInfo: request.content.userInfo,
                fallbackBody: request.content.body
            )
            let avatarURL = (request.content.userInfo["avatarURL"] as? String).flatMap(URL.init(string:))
            let avatarData = await NotificationAvatarLoader.data(from: avatarURL)
            let content: UNNotificationContent
            if let information {
                content = await CommunicationNotification.updatedContent(
                    from: request.content,
                    information: information,
                    avatarData: avatarData
                )
            } else {
                content = request.content
            }
            deliver(content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        let fallback = lock.withLock { bestAttemptContent }
        if let fallback {
            deliver(fallback)
        }
    }

    private func deliver(_ content: UNNotificationContent) {
        let handler: ((UNNotificationContent) -> Void)? = lock.withLock {
            guard !hasDelivered else { return nil }
            hasDelivered = true
            bestAttemptContent = content
            defer { contentHandler = nil }
            return contentHandler
        }
        handler?(content)
    }
}
