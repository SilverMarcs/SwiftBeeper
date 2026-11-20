import SwiftUI

/// The row opening the chat's bookmarked messages, with how many there are.
struct ChatInfoBookmarksRow: View {
    let chatID: String
    @Environment(ChatStore.self) private var chatStore

    var body: some View {
        let bookmarks = chatStore.messageBookmarks
        if bookmarks.isAvailable {
            NavigationLink(value: ChatInfoDestination.bookmarks) {
                LabeledContent {
                    if bookmarks.chatID == chatID {
                        Text(bookmarks.messageIDs.count, format: .number)
                    }
                } label: {
                    Label("Bookmarks", systemImage: "bookmark")
                }
            }
        }
    }
}
