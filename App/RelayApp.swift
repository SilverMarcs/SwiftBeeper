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
    @State private var dictationSettings = DictationSettings()
    @State private var audioPlayerService = AudioPlayerService()

    init() {
        URLProtocol.registerClass(MatrixURLProtocol.self)
        let notificationService = NotificationService()
        let chatStore = ChatStore(realtimeService: RealtimeService(), notificationService: notificationService)
        let inputManager = InputManager(chatStore: chatStore)
        AppDelegate.notificationService = notificationService
        AppDelegate.chatStore = chatStore
        AppDelegate.inputManager = inputManager
        _sessionStore = State(initialValue: SessionStore())
        _notificationService = State(initialValue: notificationService)
        _chatStore = State(initialValue: chatStore)
        _inputManager = State(initialValue: inputManager)
    }

    var body: some Scene {
        #if os(macOS)
        Window("Relay", id: "main") {
            withAppEnvironment(AppStartupView())
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1100, height: 750)

        Settings {
            withAppEnvironment(SettingsView())
        }
        #else
        WindowGroup {
            withAppEnvironment(AppStartupView())
        }
        #endif
    }

    /// Every scene gets the same app-wide stores.
    private func withAppEnvironment(_ content: some View) -> some View {
        content
            .environment(sessionStore)
            .environment(chatStore)
            .environment(inputManager)
            .environment(notificationService)
            .environment(audioPlayerService)
            .environment(dictationSettings)
    }
}
