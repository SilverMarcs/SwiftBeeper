import SwiftUI

struct OnboardingView: View {
    @Environment(ServerConnection.self) private var serverConnection
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(NotificationService.self) private var notificationService
    @State private var model = ServerSetupModel()

    var body: some View {
        Group {
            switch model.stage {
            case .automatic:
                ProgressView()
            case .remoteConnection:
                RemoteServerConnectionView(model: model, mode: .existing)
            case .remoteSetup:
                RemoteServerConnectionView(model: model, mode: .setup)
            case .beeperSignIn:
                BeeperSignInView(startsWithRecoveryKey: model.startsWithRecoveryKey)
            }
        }
        .task {
            model.configure(using: serverConnection)
        }
        .environment(serverConnection)
        .environment(sessionStore)
        .environment(chatStore)
        .environment(notificationService)
    }
}

#Preview {
    OnboardingView()
        .environment(ServerConnection())
        .environment(SessionStore())
        .environment(ChatStore())
        .environment(NotificationService())
}
