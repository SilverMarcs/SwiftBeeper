import SwiftUI

struct RemoteServerConnectionView: View {
    @Environment(ServerConnection.self) private var serverConnection
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(NotificationService.self) private var notificationService
    @Bindable var model: ServerSetupModel
    let mode: RemoteServerMode

    var body: some View {
        Form {
            Section {
                TextField("Server URL", text: $model.remoteURL)
                    .textContentType(.URL)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()

                if mode == .existing {
                    SecureField("Server Access Key", text: $model.accessKey)
                        .textContentType(.password)
                } else {
                    SecureField("Administrative setup secret", text: $model.setupSecret)
                        .textContentType(.password)
                }
            } header: {
                Text(mode == .existing ? "Connect to Server" : "Set Up Server")
            } footer: {
                if mode == .existing {
                    Text("This connects to the Matrix session already running on the server. You will not sign in to Beeper again.")
                } else {
                    Text("The setup secret is only used to administer this server. It is stored securely and never sent to normal API endpoints.")
                }
            }

            Section {
                Button(
                    mode == .existing ? "Connect" : "Continue Server Setup",
                    systemImage: "arrow.right"
                ) {
                    Task {
                        if mode == .existing {
                            await model.connectToExistingServer(
                                serverConnection: serverConnection,
                                sessionStore: sessionStore,
                                chatStore: chatStore,
                                notificationService: notificationService
                            )
                        } else {
                            await model.configureRemoteServer(
                                serverConnection: serverConnection,
                                sessionStore: sessionStore,
                                chatStore: chatStore,
                                notificationService: notificationService
                            )
                        }
                    }
                }
                .disabled(
                    model.remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || model.isWorking
                )

                if mode == .existing {
                    Button("Set Up a New Server", systemImage: "wrench.and.screwdriver") {
                        model.showRemoteSetup()
                    }
                } else {
                    Button("Connect to an Existing Server", systemImage: "network") {
                        model.showRemoteConnection()
                    }
                }

                Button("Run on This Device", systemImage: "laptopcomputer") {
                    Task {
                        await model.useEmbeddedServer(
                            serverConnection: serverConnection,
                            sessionStore: sessionStore,
                            chatStore: chatStore,
                            notificationService: notificationService
                        )
                    }
                }
            }

            if model.isWorking {
                Section {
                    ProgressView(mode == .existing ? "Connecting" : "Checking server")
                }
            } else if let errorMessage = model.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(model.isWorking)
    }
}
