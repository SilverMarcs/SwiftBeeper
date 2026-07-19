import SwiftUI

/// Shared root content for every platform: gates the UI on the in-process
/// backend becoming ready, then shows `ContentView`. The enclosing scene
/// (macOS `Window` vs iOS `WindowGroup`) lives in `RelayApp`.
struct RootView: View {
    let backend: EasyMatrixBackend
    let sessionStore: SessionStore
    let chatStore: ChatStore
    let inputManager: InputManager
    let notificationService: NotificationService
    let audioPlayerService: AudioPlayerService

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        BackendGate(backend: backend) {
            ContentView()
                .task {
                    await notificationService.requestAuthorization()
                }
                .environment(sessionStore)
                .environment(chatStore)
                .environment(inputManager)
                .environment(audioPlayerService)
        }
        .task { await backend.start() }
        .onChange(of: scenePhase) { _, newPhase in
            // iOS suspends the embedded backend (and its localhost socket) while
            // backgrounded; restart it on return so requests stop failing with
            // "Could not connect to the server", then reconnect realtime + reload.
            guard newPhase == .active else { return }
            Task {
                await backend.recoverIfNeeded()
                chatStore.handleAppForeground()
            }
        }
    }
}
