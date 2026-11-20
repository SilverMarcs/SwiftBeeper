import Foundation

/// Bookmarks of the open chat's messages, kept in Beeper's Bookmarks so the
/// account's other Beeper apps show them too.
extension ChatStore {
    /// Rereads the open chat's bookmarks. `coalescing` waits briefly first, so
    /// a burst of changes from another app costs one read; opening a chat
    /// reads at once, so its bookmarked bubbles don't fade in late.
    func refreshBookmarks(coalescing: Bool = false) {
        bookmarksTask?.cancel()
        guard let chatID = selectedChatID else {
            messageBookmarks.update(chatID: nil, isAvailable: messageBookmarks.isAvailable, messageIDs: [])
            return
        }
        if messageBookmarks.chatID != chatID {
            messageBookmarks.update(chatID: chatID, isAvailable: messageBookmarks.isAvailable, messageIDs: [])
        }
        bookmarksTask = Task { [weak self] in
            if coalescing { try? await Task.sleep(for: .milliseconds(250)) }
            guard let self, !Task.isCancelled else { return }
            guard let output = try? await APIClient.listMessageBookmarks(chatID: chatID),
                  !Task.isCancelled, selectedChatID == chatID else { return }
            messageBookmarks.update(chatID: chatID, isAvailable: output.available, messageIDs: Set(output.messageIDs))
        }
    }

    func isBookmarked(_ message: Message) -> Bool {
        messageBookmarks.contains(message.id, in: message.chatID)
    }

    /// Bookmarks or unbookmarks a message at once, then confirms with the
    /// core; a failure puts it back.
    func setBookmarked(_ message: Message, _ bookmarked: Bool) async {
        if messageBookmarks.chatID == message.chatID {
            messageBookmarks.set(message.id, bookmarked: bookmarked)
        }
        do {
            try await APIClient.setMessageBookmark(chatID: message.chatID, messageID: message.id, bookmarked: bookmarked)
        } catch {
            handleMessageError(error)
        }
        // Sync reports a change too, but a failure brings nothing back.
        if selectedChatID == message.chatID { refreshBookmarks() }
    }
}
