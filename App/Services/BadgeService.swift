import Observation
import UserNotifications

/// Opening Relay clears this device's notifications and badge.
@MainActor
@Observable
final class BadgeService {
    private(set) var isActive = false

    func configure(accessToken: String) {
        if isActive { clear() }
    }

    func setActive(_ active: Bool) {
        isActive = active
        if active { clear() }
    }

    func reconcileAfterNotification() {
        if isActive { clear() }
    }

    private func clear() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
    }
}
