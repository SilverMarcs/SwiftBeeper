import Foundation

/// Unread threads: threads with a reply that notified you since you last
/// marked them as read. Like chats, opening a thread never reads it; Mark as
/// Read clears its dot on every device, without sending a read receipt to
/// the chat's network.
extension ChatStore {
    /// Reloads the open chat's unread threads for the toolbar, coalescing a
    /// burst of thread replies into one database read.
    func refreshUnreadThreads() {
        unreadThreadsTask?.cancel()
        guard let chatID = selectedChatID else {
            unreadThreads = []
            return
        }
        unreadThreadsTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            let roots = (try? await APIClient.listUnreadThreads(chatID: chatID)) ?? []
            guard !Task.isCancelled, selectedChatID == chatID else { return }
            if unreadThreads != roots { unreadThreads = roots }
        }
    }

    /// Whether the thread starting at `root` has replies you haven't read.
    func isThreadUnread(_ root: Message) -> Bool {
        root.thread?.hasUnread == true && !threadRootIDsMarkedRead.contains(root.id)
    }

    /// Marks the thread starting at `rootID` as read, clearing its dot at
    /// once, then refreshes its root and the toolbar. The core writes only
    /// when the thread was unread.
    func markThreadAsRead(rootID: String, chatID: String) {
        threadRootIDsMarkedRead.insert(rootID)
        unreadThreads.removeAll { $0.id == rootID }
        Task { [weak self] in
            let marked = (try? await APIClient.markThreadSeen(chatID: chatID, threadRootID: rootID)) != nil
            guard let self else { return }
            defer { threadRootIDsMarkedRead.remove(rootID) }
            guard selectedChatID == chatID else { return }
            if marked, let refreshed = try? await APIClient.getMessages(chatID: chatID, messageIDs: [rootID]),
               selectedChatID == chatID {
                if messages.contains(where: { $0.id == rootID }) {
                    upsertMessages(refreshed.filter { !$0.isHiddenThreadReply })
                }
                if let activeThread, activeThread.chatID == chatID, activeThread.rootID == rootID {
                    activeThread.upsert(refreshed)
                }
            }
            // A failed write brings the thread back to the toolbar.
            refreshUnreadThreads()
        }
    }
}
