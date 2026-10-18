import SwiftUI

@main
struct RelayApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #else
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var sessionStore: SessionStore
    @State private var chatStore: ChatStore
    @State private var inputManager: InputManager
    @State private var notificationService: NotificationService
    @State private var audioPlayerService: AudioPlayerService

    init() {
        URLProtocol.registerClass(MatrixURLProtocol.self)
        let sessionStore = SessionStore()
        let notificationService = NotificationService()
        AppDelegate.notificationService = notificationService
        let audioPlayerService = AudioPlayerService()
        let chatStore = ChatStore(
            realtimeService: RealtimeService(),
            notificationService: notificationService
        )
        #if os(macOS)
        AppDelegate.chatStore = chatStore
        chatStore.handleAppActivation(NSApplication.shared.isActive)
        #endif
        _sessionStore = State(initialValue: sessionStore)
        _notificationService = State(initialValue: notificationService)
        _audioPlayerService = State(initialValue: audioPlayerService)
        _chatStore = State(initialValue: chatStore)
        _inputManager = State(initialValue: InputManager(chatStore: chatStore))

    }

    private var root: RootView {
        RootView(
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
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 750)

        Settings {
            SettingsView()
                .environment(sessionStore)
                .environment(chatStore)
                .environment(notificationService)
        }
        #else
        WindowGroup {
            root
        }
        #endif
    }
}
