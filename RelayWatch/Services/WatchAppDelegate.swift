import UserNotifications
import WatchKit

@MainActor
final class WatchAppDelegate: NSObject, WKApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching() {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let chatID = response.notification.request.content.userInfo["chatID"] as? String
            ?? response.notification.request.content.threadIdentifier
        Task { @MainActor in
            WatchNavigationCoordinator.shared.open(chatID: chatID)
        }
        completionHandler()
    }
}
