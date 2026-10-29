import SwiftUI

/// Owns sign-in and app lifecycle once the Matrix core has started and
/// reported whether an account is signed in. Waiting for that matters: treating
/// launch as signed out would clear delivered notifications and the
/// notification extension's credentials, so pushes would arrive as placeholders.
struct RootView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(NotificationService.self) private var notificationService
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ContentView()
            .alert("Couldn’t Schedule Reminder", isPresented: Binding(
                get: { notificationService.reminderErrorMessage != nil },
                set: { if !$0 { notificationService.reminderErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(notificationService.reminderErrorMessage ?? "")
            }
            .task(id: sessionStore.isSignedIn) {
                await chatStore.setSignedIn(sessionStore.isSignedIn)
            }
            .task(id: sessionStore.isSignedIn) {
                await syncCoreActivity()
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase != .inactive else { return }
                // macOS tracks app activation in AppDelegate instead, since its
                // window stays in the foreground while another app is active.
                #if os(iOS)
                chatStore.setAppActive(phase == .active)
                #endif
                Task { await syncCoreActivity() }
            }
    }

    /// The core syncs eagerly only while Relay is open and signed in.
    private func syncCoreActivity() async {
        let signedIn = sessionStore.isSignedIn
        await MatrixRuntime.shared.setActive(signedIn && scenePhase == .active)
        guard scenePhase != .background else { return }
        await notificationService.configure(signedIn: signedIn)
    }
}
