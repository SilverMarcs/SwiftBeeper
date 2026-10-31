import Foundation
import RelayCore
import OSLog
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private let delivery = NotificationDelivery()
    private let logger = Logger(subsystem: "com.SilverMarcs.Relay.notifications", category: "previews")

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        content.categoryIdentifier = NotificationCategory.message
        delivery.begin(content: content, handler: contentHandler)
        guard let roomID = content.userInfo["chatID"] as? String,
              let eventID = content.userInfo["messageID"] as? String,
              let credentials = try? NotificationCredentials.load(),
              var input = (try? JSONSerialization.jsonObject(with: credentials)) as? [String: Any] else {
            logger.error("Notification preview credentials or event identifiers unavailable")
            delivery.finish()
            return
        }
        input["roomID"] = roomID
        input["eventID"] = eventID
        input["cacheDirectory"] = URL.cachesDirectory.path
        guard let data = try? JSONSerialization.data(withJSONObject: input) else {
            delivery.finish()
            return
        }
        let delivery = delivery
        let logger = logger
        Task.detached(priority: .userInitiated) {
            let preview: NotificationPreview? = String(decoding: data, as: UTF8.self).withCString {
                guard let result = RelayNotificationPreview(UnsafeMutablePointer(mutating: $0)) else { return nil }
                defer { RelayNotificationFree(result) }
                return try? JSONDecoder().decode(NotificationPreview.self, from: Data(String(cString: result).utf8))
            }
            guard let preview, let content = delivery.prepare(preview) else {
                logger.error("Notification preview unavailable or request already completed")
                delivery.finish()
                return
            }
            let updated = await CommunicationNotification.content(from: content, preview: preview)
            logger.info("Communication notification prepared")
            delivery.finish(content: updated)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        logger.error("Notification extension time limit reached; delivering fallback")
        delivery.finish()
    }
}
