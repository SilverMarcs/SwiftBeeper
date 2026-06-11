import SwiftUI

@main
struct RelayApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var sessionStore = SessionStore()
    @State private var chatStore: ChatStore
    @State private var inputManager: InputManager
    @State private var notificationService = NotificationService()
    @State private var backend = EasyMatrixBackend.shared

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
        _inputManager = State(initialValue: InputManager(chatStore: chatStore))
        APIClient.manageSecret = EasyMatrixBackend.shared.manageSecret
        APIClient.tokenRefresher = { [sessionStore] in
            try await sessionStore.refreshAccessToken()
        }
    }

    private var root: RootView {
        RootView(
            backend: backend,
            sessionStore: sessionStore,
            chatStore: chatStore,
            inputManager: inputManager,
            notificationService: notificationService
        )
    }

    var body: some Scene {
        #if os(macOS)
        Window("Relay", id: "main") {
            root
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 750)

        Settings {
            SettingsView()
                .environment(sessionStore)
                .environment(chatStore)
        }
        #else
        WindowGroup {
            root
        }
        #endif
    }
}
