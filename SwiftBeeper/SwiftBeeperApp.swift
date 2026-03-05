import SwiftUI

@main
struct SwiftBeeperApp: App {
    @State private var sessionStore = SessionStore()
    @State private var chatStore = ChatStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionStore)
                .environment(chatStore)
                .environment(chatStore.messageStore)
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(sessionStore)
        }
        #endif
    }
}
