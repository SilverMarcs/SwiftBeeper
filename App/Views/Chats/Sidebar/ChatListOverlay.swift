import SwiftUI

/// A spinner while searching or loading an empty list, the load error, or
/// a search that found nothing.
struct ChatListOverlay: View {
    @Environment(ChatStore.self) private var chatStore

    let isEmpty: Bool

    var body: some View {
        if chatStore.isSearching || (isEmpty && chatStore.isLoadingChats) {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isEmpty, chatStore.isSearchActive, chatStore.searchResults != nil {
            ContentUnavailableView.search(text: chatStore.searchQuery.trimmed)
        } else if isEmpty,
                  !chatStore.isSearchActive,
                  let chatsError = chatStore.chatsError {
            ContentUnavailableView(
                "Could Not Load Chats",
                systemImage: "exclamationmark.triangle",
                description: Text(chatsError)
            )
        }
    }
}
