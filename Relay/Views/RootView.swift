import SwiftUI

/// Shared root content for every platform. The enclosing scene
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
        ContentView()
            .task {
                await notificationService.requestAuthorization()
            }
            .task(id: sessionStore.accessToken) {
                await notificationService.syncRemoteRegistration()
            }
            .environment(sessionStore)
            .environment(chatStore)
            .environment(inputManager)
            .environment(notificationService)
            .environment(audioPlayerService)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    chatStore.handleAppForeground()
                    Task { await notificationService.syncRemoteRegistration() }
                } else {
                    chatStore.handleAppBackground()
                }
            }
    }
}
