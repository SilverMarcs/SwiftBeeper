import SwiftUI

/// Shared root content for every platform: prepares the selected server, then
/// shows `ContentView`. The enclosing scene
/// (macOS `Window` vs iOS `WindowGroup`) lives in `RelayApp`.
struct RootView: View {
    let serverConnection: ServerConnection
    let sessionStore: SessionStore
    let chatStore: ChatStore
    let inputManager: InputManager
    let notificationService: NotificationService
    let audioPlayerService: AudioPlayerService

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        BackendGate(serverConnection: serverConnection) {
            ContentView()
                .task {
                    await notificationService.requestAuthorization()
                }
                .environment(sessionStore)
                .environment(chatStore)
                .environment(inputManager)
                .environment(notificationService)
                .environment(audioPlayerService)
        }
        .task { await serverConnection.prepare() }
        .task(id: sessionStore.accessToken) {
            await notificationService.syncRemoteRegistration()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await serverConnection.recoverIfNeeded()
                    chatStore.handleAppForeground()
                    await notificationService.syncRemoteRegistration()
                }
            } else {
                chatStore.handleAppBackground()
            }
        }
    }
}
