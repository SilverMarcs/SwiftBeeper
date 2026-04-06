import SwiftUI

@main
struct SwiftBeeperApp: App {
    @State private var sessionStore = SessionStore()
    @State private var chatStore = ChatStore()
    @State private var messageStore = MessageStore()
    @State private var realtimeService = RealtimeService()
    @State private var notificationService = NotificationService()
    @State private var coordinator: RealtimeCoordinator

    init() {
        // MARK: - Auto-launch EasyMatrix server (comment out these 4 lines to disable)
        EasyMatrixServer.shared.start()
        AppTerminationObserver.shared.register()
        // END auto-launch

        let chatStore = ChatStore()
        let messageStore = MessageStore()
        let realtimeService = RealtimeService()
        let notificationService = NotificationService()
        notificationService.messageStore = messageStore
        notificationService.chatStore = chatStore
        _chatStore = State(initialValue: chatStore)
        _messageStore = State(initialValue: messageStore)
        _realtimeService = State(initialValue: realtimeService)
        _notificationService = State(initialValue: notificationService)
        _coordinator = State(initialValue: RealtimeCoordinator(
            chatStore: chatStore,
            messageStore: messageStore,
            realtimeService: realtimeService,
            notificationService: notificationService
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionStore)
                .environment(chatStore)
                .environment(messageStore)
                .environment(coordinator)
                .task {
                    await notificationService.requestAuthorization()
                }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(sessionStore)
        }
        #endif
    }
}

#if os(macOS)
/// Monitors app termination to cleanly stop the EasyMatrix server.
final class AppTerminationObserver {
    static let shared = AppTerminationObserver()
    private var observation: Any?

    func register() {
        guard observation == nil else { return }
        observation = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            EasyMatrixServer.shared.stop()
        }
    }
}
#endif
