#if DEBUG && os(macOS)
import SwiftUI

struct PushPrivacyTestSection: View {
    @Bindable var model: ServerSettingsModel

    var body: some View {
        Section {
            TextField("Temporary HTTPS tunnel URL", text: $model.pushPrivacyTestURL)
                .textContentType(.URL)
                .autocorrectionDisabled()

            SecureField("Temporary management secret", text: $model.pushPrivacyTestManageSecret)
                .textContentType(.password)

            HStack {
                Button("Register Test Pusher", systemImage: "bell.badge") {
                    Task { await model.registerPushPrivacyTest() }
                }
                .disabled(
                    model.isUpdatingPushPrivacyTest
                    || model.pushPrivacyTestURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || model.pushPrivacyTestManageSecret.isEmpty
                )

                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await model.refreshPushPrivacyTest() }
                }
                .disabled(model.isUpdatingPushPrivacyTest || model.pushPrivacyTestManageSecret.isEmpty)

                if model.pushPrivacyTestState?.registered == true {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        Task { await model.removePushPrivacyTest() }
                    }
                    .disabled(model.isUpdatingPushPrivacyTest || model.pushPrivacyTestManageSecret.isEmpty)
                }
            }

            if model.isUpdatingPushPrivacyTest {
                ProgressView()
            }

            if let notification = model.pushPrivacyTestState?.lastNotification {
                LabeledContent("Last event", value: notification.eventID ?? "Unknown")
                LabeledContent("Room", value: notification.roomID ?? "Unknown")
                LabeledContent("Fields", value: notification.fields.joined(separator: ", "))
                Text(
                    notification.hadContent || notification.hadSender
                        ? "Privacy check failed: Beeper included content or sender metadata."
                        : "Privacy check passed: the gateway received no content or sender metadata."
                )
                .foregroundStyle(notification.hadContent || notification.hadSender ? .red : .green)
            } else if let message = model.pushPrivacyTestMessage {
                Text(message)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Push Privacy Test")
        } footer: {
            Text("Debug-only. The management secret stays in memory. The server records push metadata without retaining notification content.")
        }
    }
}
#endif
