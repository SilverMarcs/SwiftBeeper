import Foundation
import Observation
import UserNotifications

@MainActor @Observable
final class SettingsModel {
    let context: AppContext
    var error: String?
    var isSigningOut = false
    var autoplay: Bool {
        didSet { UserDefaults.standard.set(autoplay, forKey: "autoplay") }
    }
    var muteOnPlay: Bool {
        didSet { UserDefaults.standard.set(muteOnPlay, forKey: "muteOnPlay") }
    }
    var notificationStatus: String {
        let service = context.notifications
        if service.isPreparing || service.isRegistering { return "Connecting…" }
        if let status = service.authorizationStatus {
            if status == .denied { return "Disabled in System Settings" }
            if status == .notDetermined { return "Not enabled" }
        }
        return service.errorMessage == nil && (service.authorizationStatus == .authorized || service.authorizationStatus == .provisional) ? "Enabled" : "Not connected"
    }
    init(context: AppContext) {
        self.context = context
        autoplay = UserDefaults.standard.object(forKey: "autoplay") as? Bool ?? true
        muteOnPlay = UserDefaults.standard.bool(forKey: "muteOnPlay")
    }
    func refresh() async { await context.notifications.refreshAuthorizationStatus() }
    func reconnect() async {
        await context.notifications.configure(signedIn: !context.session.accessToken.isEmpty, force: true)
        error = context.notifications.errorMessage
    }
    func clearCache() { NativeImages.clear() }
    func signOut() async {
        guard !isSigningOut else { return }; isSigningOut = true
        defer { isSigningOut = false }
        do {
            try await context.notifications.prepareForSignOut()
            _ = try await MatrixRuntime.shared.command(Data("{\"action\":\"logout\"}".utf8))
            context.session.clearToken()
        } catch {
            self.error = error.localizedDescription
            await context.notifications.configure(signedIn: !context.session.accessToken.isEmpty)
        }
    }
}
