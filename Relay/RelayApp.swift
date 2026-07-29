import SwiftUI

@main
struct RelayApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #else
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var serverConnection: ServerConnection
    @State private var sessionStore: SessionStore
    @State private var chatStore: ChatStore
    @State private var inputManager: InputManager
    @State private var notificationService: NotificationService
    @State private var audioPlayerService: AudioPlayerService

    init() {
        let serverConnection = ServerConnection()
        let sessionStore = SessionStore(endpointIdentity: serverConnection.endpoint.identity)
        let notificationService = NotificationService()
        let audioPlayerService = AudioPlayerService()
        let chatStore = ChatStore(
            realtimeService: RealtimeService(),
            notificationService: notificationService
        )
        notificationService.store = chatStore
        notificationService.serverConnection = serverConnection
        notificationService.sessionStore = sessionStore
        #if os(iOS)
        AppDelegate.notificationService = notificationService
        #endif
        _serverConnection = State(initialValue: serverConnection)
        _sessionStore = State(initialValue: sessionStore)
        _notificationService = State(initialValue: notificationService)
        _audioPlayerService = State(initialValue: audioPlayerService)
        _chatStore = State(initialValue: chatStore)
        _inputManager = State(initialValue: InputManager(chatStore: chatStore))
        APIClient.tokenRefresher = { [sessionStore] in
            try await sessionStore.refreshAccessToken()
        }
    }

    private var root: RootView {
        RootView(
            serverConnection: serverConnection,
            sessionStore: sessionStore,
            chatStore: chatStore,
            inputManager: inputManager,
            notificationService: notificationService,
            audioPlayerService: audioPlayerService
        )
    }

    var body: some Scene {
        #if os(macOS)
        Window("Relay", id: "main") {
            root
                .environment(serverConnection)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 750)

        Settings {
            SettingsView()
                .environment(serverConnection)
                .environment(sessionStore)
                .environment(chatStore)
                .environment(notificationService)
        }
        #else
        WindowGroup {
            root
                .environment(serverConnection)
        }
        #endif
    }
}
