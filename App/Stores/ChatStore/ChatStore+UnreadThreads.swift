import Foundation

/// Unread threads: threads with a reply that notified you since you last
/// opened them. Opening a thread clears its dot on every device, without
/// sending a read receipt to the chat's network.
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

    /// Records that `thread` is on screen, then refreshes its root's dot and
    /// the toolbar. The core writes only when the thread was unread.
    func markThreadSeen(_ thread: ThreadStore) {
        let chatID = thread.chatID
        let rootID = thread.rootID
        Task { [weak self] in
            guard (try? await APIClient.markThreadSeen(chatID: chatID, threadRootID: rootID)) != nil,
                  let self, selectedChatID == chatID else { return }
            if messages.contains(where: { $0.id == rootID && $0.thread?.hasUnread == true }),
               let refreshed = try? await APIClient.getMessages(chatID: chatID, messageIDs: [rootID]),
               selectedChatID == chatID {
                upsertMessages(refreshed.filter { !$0.isHiddenThreadReply })
            }
            refreshUnreadThreads()
        }
    }
}
