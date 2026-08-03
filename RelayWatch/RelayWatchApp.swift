import SwiftUI
import WatchKit

@main
struct RelayWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @State private var store = WatchChatStore()

    var body: some Scene {
        WindowGroup {
            WatchChatListView()
                .environment(store)
                .environment(WatchNavigationCoordinator.shared)
                .task { await store.start() }
        }
    }
}
