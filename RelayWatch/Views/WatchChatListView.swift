import SwiftUI

struct WatchChatListView: View {
    @Environment(WatchChatStore.self) private var store
    @Environment(WatchNavigationCoordinator.self) private var navigation
    @State private var path: [String] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.chats.isEmpty && !store.isLoadingChats {
                    ContentUnavailableView(
                        "No Cached Chats",
                        systemImage: "iphone.and.arrow.forward",
                        description: Text(store.errorMessage ?? "Keep your paired iPhone nearby, then refresh.")
                    )
                } else {
                    List(store.chats) { chat in
                        NavigationLink(value: chat.id) {
                            WatchChatRow(chat: chat)
                        }
                    }
                }
            }
            .navigationTitle("Chats")
            .navigationDestination(for: String.self) { chatID in
                WatchMessageListView(chatID: chatID)
            }
            .overlay {
                if store.isLoadingChats && store.chats.isEmpty {
                    ProgressView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await store.refreshChats() }
                    }
                    .disabled(store.isLoadingChats)
                }
            }
        }
        .task { openPendingNotification() }
        .onChange(of: navigation.pendingChatID) {
            openPendingNotification()
        }
    }

    private func openPendingNotification() {
        guard let chatID = navigation.takePendingChatID() else { return }
        path = [chatID]
    }
}
