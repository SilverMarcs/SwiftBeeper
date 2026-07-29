import SwiftUI

struct ServerChoiceView: View {
    @Environment(ServerConnection.self) private var serverConnection
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(NotificationService.self) private var notificationService
    let model: ServerSetupModel

    var body: some View {
        VStack {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.largeTitle)
                .foregroundStyle(.tint)

            Text("Choose Your Server")
                .font(.title.bold())

            Text("Relay can run EasyMatrix here or connect to one that is already running elsewhere.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("The Matrix session and data stay on this device.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Connect to Remote Server", systemImage: "network") {
                model.showRemoteConnection()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text("Use a server that is already signed in and running.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if model.isWorking {
                ProgressView("Starting EasyMatrix")
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(model.isWorking)
    }
}
