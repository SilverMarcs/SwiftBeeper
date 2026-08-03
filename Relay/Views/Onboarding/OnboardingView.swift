import SwiftUI

struct OnboardingView: View {
    #if REMOTE_ONLY
    @Environment(ServerConnection.self) private var serverConnection
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(NotificationService.self) private var notificationService
    @State private var model = ServerSetupModel()
    #endif

    var body: some View {
        #if REMOTE_ONLY
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
        #else
        BeeperSignInView(startsWithRecoveryKey: false)
        #endif
    }
}

#Preview {
    OnboardingView()
        .environment(ServerConnection())
        .environment(SessionStore())
        .environment(ChatStore())
        .environment(NotificationService())
}
