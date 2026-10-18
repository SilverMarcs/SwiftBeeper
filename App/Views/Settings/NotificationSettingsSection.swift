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
                if let authorization = notificationService.authorizationStatus {
                    Button(authorization == .authorized || authorization == .provisional ? "Reconnect" : "Allow", action: handleAction)
                        .disabled(notificationService.isPreparing || notificationService.isRegistering)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        }
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

    private func handleAction() {
        if notificationService.authorizationStatus == .denied {
            #if os(macOS)
            let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
            #else
            let settingsURL = URL(string: UIApplication.openNotificationSettingsURLString)
            #endif
            if let settingsURL { openURL(settingsURL) }
        } else {
            Task { await notificationService.configure(signedIn: true, force: true) }
        }
    }
}
