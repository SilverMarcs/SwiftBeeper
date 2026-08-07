import SwiftUI
import WatchKit

@main
struct RelayWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = WatchChatStore()
    @State private var navigation = WatchNavigationCoordinator.shared

    var body: some Scene {
        WindowGroup {
            WatchChatListView()
                .environment(store)
                .environment(navigation)
                .task { await store.start() }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }

                    Task {
                        if let chatID = navigation.visibleChatID {
                            await store.refreshMessages(for: chatID)
                        } else {
                            await store.refreshChats()
                        }
                    }
                }
        }
    }
}
