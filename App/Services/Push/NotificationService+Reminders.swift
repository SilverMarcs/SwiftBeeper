import Foundation
import UserNotifications

extension NotificationService {
    /// The notification center owns the timer, including while Relay is closed.
    func remindToReply(to chat: Chat, after delay: ChatReminderDelay) async {
        guard isSignedIn else { return }
        reminderErrorMessage = nil
        let center = UNUserNotificationCenter.current()
        do {
            var settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                settings = await center.notificationSettings()
            }
            await refreshAuthorizationStatus()
            guard isSignedIn else { return }
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                reminderErrorMessage = "Allow notifications for Relay in Settings to receive reply reminders."
                return
            }

            let content = UNMutableNotificationContent()
            content.title = chat.displayTitle
            content.body = String(localized: "Remember to reply to this conversation.")
            content.sound = .default
            content.categoryIdentifier = NotificationCategory.reminder
            content.threadIdentifier = chat.id
            content.userInfo = ["chatID": chat.id]
            // A new time replaces this conversation's existing pending reminder.
            let request = UNNotificationRequest(
                identifier: "reply-reminder-\(chat.id)",
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay.rawValue, repeats: false)
            )
            try await center.add(request)
            if !isSignedIn {
                center.removePendingNotificationRequests(withIdentifiers: [request.identifier])
            }
        } catch {
            if isSignedIn { reminderErrorMessage = error.localizedDescription }
        }
    }
}
