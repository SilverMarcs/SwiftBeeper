import Foundation

/// Threads: opening one beside (or over) the open chat's timeline. Replies
/// go through the shared outbox, from the thread's own composer.
extension ChatStore {
    /// Opens the thread `message` starts, or the one it replies in.
    func showThread(for message: Message) {
        let rootID = message.threadRootID ?? message.id
        if isThreadPresented, let activeThread, activeThread.rootID == rootID, activeThread.chatID == message.chatID {
            return
        }
        guard let chat = chat(byID: message.chatID) else { return }
        activeThread?.cancel()
        let root = rootID == message.id ? message : messages.first { $0.id == rootID } ?? quotedMessages[rootID]
        let thread = ThreadStore(chat: chat, rootID: rootID, root: root, chatStore: self)
        activeThread = thread
        isThreadPresented = true
        thread.load()
    }

    func closeThread() {
        isThreadPresented = false
    }

    /// The thread's optimistic rows.
    func outgoingMessages(in thread: ThreadStore) -> [OutgoingMessage] {
        (outgoingMessagesByChatID[thread.chatID] ?? []).filter { $0.threadRootID == thread.rootID }
    }
}
