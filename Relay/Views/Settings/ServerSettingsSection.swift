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
            Picker("EasyMatrix", selection: $model.location) {
                ForEach(ServerLocation.allCases) { location in
                    Text(location.title)
                        .tag(location)
                }
            }
            .pickerStyle(.segmented)

            if model.location == .remote {
                TextField("Server URL", text: $model.remoteURL)
                    .textContentType(.URL)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()

                SecureField("Server Access Key", text: $model.accessKey)
                    .textContentType(.password)
            }

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
                || serverConnection.isSwitching
                || (
                    model.location == .remote
                    && model.remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            )

            if serverConnection.isSwitching {
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
            if model.location == .remote {
                Text("The server owns the Matrix session. Leave the access key blank to keep using the saved key for this URL.")
            } else {
                Text("Relay runs EasyMatrix locally and signs this device in to Matrix.")
            }
        }
        .onAppear {
            model.configure(using: serverConnection)
        }
    }
}
