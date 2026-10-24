import SwiftUI
import UserNotifications

struct NotificationSettingsSection: View {
    @Environment(NotificationService.self) private var notificationService
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingError = false

    var body: some View {
        Section {
            LabeledContent("Notifications") {
                switch notificationService.authorizationStatus {
                case .denied:
                    Button("Open Settings", action: openNotificationSettings)
                case .notDetermined:
                    Button("Allow", action: reconnect)
                case .authorized, .provisional:
                    if notificationService.errorMessage != nil {
                        Button("Retry", action: reconnect)
                    } else if notificationService.isRegistered {
                        Text("On")
                            .foregroundStyle(.secondary)
                    } else {
                        // Waiting for Apple's push token or the push server.
                        ProgressView().controlSize(.small)
                    }
                case nil:
                    ProgressView().controlSize(.small)
                #if os(iOS)
                case .ephemeral:
                    // Only App Clips get ephemeral authorization.
                    Button("Retry", action: reconnect)
                #endif
                @unknown default:
                    Button("Retry", action: reconnect)
                }
            }
        }
        .disabled(notificationService.isPreparing || notificationService.isRegistering)
        .task { await notificationService.refreshAuthorizationStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await notificationService.refreshAuthorizationStatus() }
            }
        }
        .onChange(of: notificationService.errorMessage) { _, message in
            if message != nil { showingError = true }
        }
        .alert("Notifications", isPresented: $showingError, presenting: notificationService.errorMessage) { _ in
            Button("OK", role: .cancel) { }
        } message: { message in
            Text(message)
        }
    }

    /// Asks again for permission, or registers again with a fresh Apple token.
    private func reconnect() {
        Task { await notificationService.configure(signedIn: true, force: true) }
    }

    private func openNotificationSettings() {
        #if os(macOS)
        let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        #else
        let settingsURL = URL(string: UIApplication.openNotificationSettingsURLString)
        #endif
        if let settingsURL { openURL(settingsURL) }
    }
}
