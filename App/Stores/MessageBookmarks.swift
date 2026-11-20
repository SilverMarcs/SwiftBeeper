import Foundation
import Observation

/// The open chat's bookmarked messages. Its own observable, so a change
/// redraws only the bubbles and menus that read it, not every row.
@MainActor
@Observable
final class MessageBookmarks {
    /// The chat these IDs belong to.
    private(set) var chatID: String?
    /// Whether the account has Beeper's Bookmarks. Assumed until the first
    /// read, so the menu doesn't change under the reader.
    private(set) var isAvailable = true
    private(set) var messageIDs: Set<Message.ID> = []

    func contains(_ messageID: Message.ID, in chatID: String) -> Bool {
        self.chatID == chatID && messageIDs.contains(messageID)
    }

    func update(chatID: String?, isAvailable: Bool, messageIDs: Set<Message.ID>) {
        self.chatID = chatID
        self.isAvailable = isAvailable
        self.messageIDs = messageIDs
    }

    /// Applies a change before the core confirms it.
    func set(_ messageID: Message.ID, bookmarked: Bool) {
        if bookmarked {
            messageIDs.insert(messageID)
        } else {
            messageIDs.remove(messageID)
        }
    }
}
