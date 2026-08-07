import SwiftUI

struct WatchMessageListView: View {
    @Environment(WatchChatStore.self) private var store
    @Environment(WatchNavigationCoordinator.self) private var navigation
    let chatID: String

    var body: some View {
        let messages = store.messages(for: chatID)

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if messages.isEmpty && !store.isLoadingMessages(for: chatID) {
                        ContentUnavailableView(
                            "No Cached Messages",
                            systemImage: "message",
                            description: Text(store.errorMessage ?? "Refresh with your paired iPhone nearby.")
                        )
                    } else if store.isLoadingMessages(for: chatID) && store.messages(for: chatID).isEmpty {
                        ProgressView()
                    } else {
                        ForEach(messages.enumerated(), id: \.element.id) { index, message in
                            WatchMessageRow(message: message)
                                .padding(
                                    .top,
                                    index == messages.startIndex
                                        ? 0
                                        : messages[index - 1].isOutgoing == message.isOutgoing ? 2 : 8
                                )
                        }
                    }

                    WatchMessageComposer(chatID: chatID)
                        .padding(.top)
                }
            }
            .scrollIndicators(.hidden)
            .onAppear {
                guard let messageID = messages.last?.id else { return }
                proxy.scrollTo(messageID, anchor: .bottom)
            }
            .onChange(of: messages.last?.id) { _, messageID in
                guard let messageID else { return }
                withAnimation {
                    proxy.scrollTo(messageID, anchor: .bottom)
                }
            }
        }
        .navigationTitle(store.title(for: chatID))
        .overlay {
            if store.isLoadingMessages(for: chatID) && store.messages(for: chatID).isEmpty {
                ProgressView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                WatchChatAvatarView(
                    title: store.title(for: chatID),
                    imageURL: store.avatarURL(for: chatID),
                    dimension: 32
                )
            }

            /* Keep this available if manual refresh returns to the toolbar.
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await store.refreshMessages(for: chatID) }
                }
                .disabled(store.isLoadingMessages(for: chatID))
            }
            */
        }
        .task(id: chatID) {
            await store.refreshMessages(for: chatID)
        }
        .onAppear {
            navigation.show(chatID: chatID)
        }
        .onDisappear {
            navigation.hide(chatID: chatID)
        }
    }
}
