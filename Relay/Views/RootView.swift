import SwiftUI

/// Shared root content for every platform: gates the UI on the in-process
/// backend becoming ready, then shows `ContentView`. The enclosing scene
/// (macOS `Window` vs iOS `WindowGroup`) lives in `RelayApp`.
struct RootView: View {
    let backend: EasyMatrixBackend
    let sessionStore: SessionStore
    let chatStore: ChatStore
    let notificationService: NotificationService

    var body: some View {
        BackendGate(backend: backend) {
            ContentView()
                .task {
                    await notificationService.requestAuthorization()
                }
                .environment(sessionStore)
                .environment(chatStore)
        }
        .task { await backend.start() }
    }
}
