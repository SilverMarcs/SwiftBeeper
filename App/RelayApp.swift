import SwiftUI
#if os(macOS)
import RelayUpdates
#endif

@main
struct RelayApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appUpdater = AppUpdater()
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
        MatrixMedia.registerImageSource()
        PendingAttachmentImageSource.register()
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
        Task { await chatStore.observeShareExtension() }
    }

    var body: some Scene {
        #if os(macOS)
        Window("Relay", id: "main") {
            withAppEnvironment(AppStartupView().mainWindowMinimumSize())
        }
        .defaultSize(width: 1100, height: 750)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { appUpdater.checkForUpdates() }
                    .disabled(!appUpdater.canCheckForUpdates)
            }
            ComposerFormatCommands()
            ChatTextSizeCommands()
        }

        Settings {
            withAppEnvironment(SettingsView())
        }
        #else
        WindowGroup {
            #if DEBUG
            if TimelineLabController.isEnabled {
                withAppEnvironment(TimelineLabRootView())
            } else {
                withAppEnvironment(AppStartupView())
            }
            #else
            withAppEnvironment(AppStartupView())
            #endif
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
