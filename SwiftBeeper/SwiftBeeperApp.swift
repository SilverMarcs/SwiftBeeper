import SwiftUI

@main
struct SwiftBeeperApp: App {
    @State private var sessionStore = SessionStore()
    @State private var chatStore = ChatStore()
    @State private var messageStore = MessageStore()
    @State private var realtimeService = RealtimeService()
    @State private var coordinator: RealtimeCoordinator

    init() {
        let chatStore = ChatStore()
        let messageStore = MessageStore()
        let realtimeService = RealtimeService()
        _chatStore = State(initialValue: chatStore)
        _messageStore = State(initialValue: messageStore)
        _realtimeService = State(initialValue: realtimeService)
        _coordinator = State(initialValue: RealtimeCoordinator(
            chatStore: chatStore,
            messageStore: messageStore,
            realtimeService: realtimeService
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionStore)
                .environment(chatStore)
                .environment(messageStore)
                .environment(coordinator)
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(sessionStore)
        }
        #endif
    }
}
