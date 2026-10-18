import SwiftUI

struct ChatListOverlay: View {
    @Environment(ChatStore.self) private var chatStore

    let isEmpty: Bool

    var body: some View {
        if chatStore.isSearching
            || (isEmpty && (
                chatStore.isLoadingChats
            )) {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isEmpty,
                  chatStore.searchQuery.isBlank,
                  let chatsError = chatStore.chatsError {
            ContentUnavailableView(
                "Could Not Load Chats",
                systemImage: "exclamationmark.triangle",
                description: Text(chatsError)
            )
        }
    }
}
