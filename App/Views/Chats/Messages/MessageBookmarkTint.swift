import SwiftUI

/// Marks a bookmarked message's bubbles for their warm fill. A modifier of
/// its own, so a bookmark change redraws only the rows it affects rather
/// than every row reading the bookmarks.
struct MessageBookmarkTint: ViewModifier {
    /// The row's messages: a gallery folds several into one row.
    let messageIDs: [Message.ID]
    let chatID: String
    @Environment(ChatStore.self) private var chatStore

    func body(content: Content) -> some View {
        let bookmarks = chatStore.messageBookmarks
        let isBookmarked = messageIDs.contains { bookmarks.contains($0, in: chatID) }
        content.environment(\.isBookmarkedBubble, isBookmarked)
    }
}

extension EnvironmentValues {
    /// Whether the bubbles belong to a bookmarked message.
    @Entry var isBookmarkedBubble = false
}
