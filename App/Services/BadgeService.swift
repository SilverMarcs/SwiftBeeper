import Observation
import UserNotifications

/// Opening Relay clears the badge; conversation selection clears its alerts.
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
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(0) }
    }
}
