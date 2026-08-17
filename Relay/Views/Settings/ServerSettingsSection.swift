import SwiftUI

struct ServerSettingsSection: View {
    @Environment(ServerConnection.self) private var serverConnection
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(NotificationService.self) private var notificationService
    @State private var model = ServerSettingsModel()

    var body: some View {
        @Bindable var model = model

        Section {
            TextField("Server URL", text: $model.remoteURL)
                .textContentType(.URL)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

            SecureField("Server Access Key", text: $model.accessKey)
                .textContentType(.password)

            Button("Apply", systemImage: "checkmark") {
                Task {
                    await model.apply(
                        serverConnection: serverConnection,
                        sessionStore: sessionStore,
                        chatStore: chatStore,
                        notificationService: notificationService
                    )
                }
            }
            .disabled(
                !model.hasChanges(using: serverConnection)
                || serverConnection.isUpdatingRemoteServer
                || model.remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )

            if serverConnection.isUpdatingRemoteServer {
                ProgressView("Connecting")
            } else if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else if let savedMessage = model.savedMessage {
                Text(savedMessage)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Server")
        } footer: {
            Text("The server owns the Matrix session. Leave the access key blank to keep using the saved key for this URL.")
        }
        .onAppear {
            model.configure(using: serverConnection)
        }
    }
}
