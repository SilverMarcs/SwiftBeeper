import SwiftUI

/// Shared root content for every platform. The enclosing scene
/// (macOS `Window` vs iOS `WindowGroup`) lives in `RelayApp`.
struct RootView: View {
    let sessionStore: SessionStore
    let chatStore: ChatStore
    let inputManager: InputManager
    let notificationService: NotificationService
    let audioPlayerService: AudioPlayerService

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            AppStartupView()
        }
            .task {
                #if os(macOS)
                notificationService.badges.setActive(NSApplication.shared.isActive)
                #else
                notificationService.badges.setActive(scenePhase == .active)
                if scenePhase == .active { chatStore.handleAppForeground() }
                #endif
            }
            .task(id: sessionStore.accessToken) {
                await MatrixRuntime.shared.setActive(!sessionStore.accessToken.isEmpty && scenePhase == .active)
                await notificationService.configure(signedIn: !sessionStore.accessToken.isEmpty)
            }
            .environment(sessionStore)
            .environment(chatStore)
            .environment(inputManager)
            .environment(notificationService)
            .environment(audioPlayerService)
            .onChange(of: scenePhase) { _, newPhase in
                Task {
                    if newPhase == .active {
                        await MatrixRuntime.shared.setActive(!sessionStore.accessToken.isEmpty)
                        await notificationService.configure(signedIn: !sessionStore.accessToken.isEmpty)
                    } else if newPhase == .background {
                        await MatrixRuntime.shared.setActive(false)
                    }
                }
                if newPhase == .active {
                    chatStore.handleAppForeground()
                } else if newPhase == .background {
                    chatStore.handleAppBackground()
                }
            }
    }

}
