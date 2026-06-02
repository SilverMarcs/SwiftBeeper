import SwiftUI

@main
struct RelayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var sessionStore = SessionStore()
    @State private var chatStore: ChatStore
    @State private var notificationService = NotificationService()
    @State private var backend = EasyMatrixProcess.shared

    init() {
        let sessionStore = SessionStore()
        let notificationService = NotificationService()
        let chatStore = ChatStore(
            realtimeService: RealtimeService(),
            notificationService: notificationService
        )
        notificationService.store = chatStore
        _sessionStore = State(initialValue: sessionStore)
        _notificationService = State(initialValue: notificationService)
        _chatStore = State(initialValue: chatStore)
        APIClient.manageSecret = EasyMatrixProcess.shared.manageSecret
        APIClient.tokenRefresher = { [sessionStore] in
            try await sessionStore.refreshAccessToken()
        }
    }

    var body: some Scene {
        Window("Relay", id: "main") {
            BackendGate(backend: backend) {
                ContentView()
                    .task {
                        await notificationService.requestAuthorization()
                    }
                    .environment(sessionStore)
                    .environment(chatStore)
            }
            .frame(minWidth: 900, minHeight: 600)
            .task { await backend.start() }
        }
        .defaultSize(width: 1100, height: 750)

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(sessionStore)
        }
        #endif
    }
}
