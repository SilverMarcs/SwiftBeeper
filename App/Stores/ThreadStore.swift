import Foundation
import Observation

/// One open thread: its root and replies. `ChatStore` owns the open thread
/// and forwards the chat's realtime messages to it; replies go through
/// ChatStore's shared outbox from the thread's own `Composer`.
@MainActor
@Observable
final class ThreadStore {
    /// The chat as it was when the thread opened.
    let chat: Chat
    let rootID: String
    var chatID: String { chat.id }

    /// The thread's first message. Nil until loaded when the thread opened
    /// from a reply whose root isn't in the timeline.
    private(set) var root: Message?
    /// Replies, oldest first. Server-fetched replies have no timeline
    /// position, so the thread orders by time like the network does.
    private(set) var replies: [Message] = []
    private(set) var hasLoadedTimeline = false
    private(set) var isLoadingTimeline = false
    var error: String?

    @ObservationIgnored private weak var chatStore: ChatStore?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(chat: Chat, rootID: String, root: Message?, chatStore: ChatStore) {
        self.chat = chat
        self.rootID = rootID
        self.root = root
        self.chatStore = chatStore
    }

    // MARK: - Loading

    /// Shows the local replies, then fetches the thread from the server, since
    /// sync only delivers replies sent while this device followed the chat. A
    /// resync after reconnecting passes `fetchingHistory: false`: the history
    /// was fetched when the thread opened, and sync has kept it current since.
    func load(fetchingHistory: Bool = true) {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            await loadLocal()
            guard fetchingHistory, !Task.isCancelled else { return }
            do {
                try await APIClient.loadThreadHistory(chatID: chatID, threadRootID: rootID)
                guard !Task.isCancelled else { return }
                await loadLocal()
            } catch {
                guard !Task.isCancelled, replies.isEmpty else { return }
                self.error = error.localizedDescription
            }
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }

    private func loadLocal() async {
        isLoadingTimeline = true
        defer { isLoadingTimeline = false }
        do {
            let output = try await APIClient.listThread(chatID: chatID, threadRootID: rootID)
            guard !Task.isCancelled else { return }
            if let root = output.root { self.root = root }
            upsert(output.items)
            hasLoadedTimeline = true
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    /// Applies the chat's changed messages, keeping the root and this
    /// thread's replies. Every copy the core sends is complete.
    func upsert(_ incoming: [Message]) {
        // Every change in the chat arrives here while the thread is open;
        // most belong to other threads or the main timeline.
        if let newRoot = incoming.last(where: { $0.id == rootID }), newRoot != root {
            root = newRoot
        }
        let threadReplies = incoming.filter { $0.id != rootID && $0.threadRootID == rootID }
        guard !threadReplies.isEmpty else { return }
        var byID = Dictionary(replies.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for message in threadReplies {
            byID[message.id] = message
        }
        let updated = byID.values.sorted { ($0.timestamp, $0.numericSortKey, $0.id) < ($1.timestamp, $1.numericSortKey, $1.id) }
        if updated != replies { replies = updated }
    }
}

// MARK: - TimelineSource

extension ThreadStore: TimelineSource {
    var timelineChat: Chat? { chat }

    var composerTarget: ComposerTarget? {
        ComposerTarget(chatID: chatID, threadRootID: rootID)
    }

    /// The root leads the thread like any other message.
    var timelineMessages: [Message] {
        let shownByOutgoingRows = Set(timelineOutgoingMessages.flatMap(\.confirmedMessageIDs))
        let replies = shownByOutgoingRows.isEmpty ? replies : replies.filter { !shownByOutgoingRows.contains($0.id) }
        return (root.map { [$0] } ?? []) + replies
    }

    var timelineOutgoingMessages: [OutgoingMessage] {
        chatStore?.outgoingMessages(in: self) ?? []
    }

    var typingBubble: TypingBubble? { nil }
    var typingMessageRowIDs: [Message.ID: String] { [:] }
    var quotedMessages: [Message.ID: Message] { [:] }
    var lastReadByOtherSortKey: String? { nil }
    var showsUnreadDivider: Bool { false }
    var isLoadingOlderTimeline: Bool { false }
    var canLoadServerHistory: Bool { false }
    var timelineError: String? { error }

    func loadTimeline() async {
        load()
    }

    func loadOlderTimeline() async {}
    func loadServerHistory() async {}
}
