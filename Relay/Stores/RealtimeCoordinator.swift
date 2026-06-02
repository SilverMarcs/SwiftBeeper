import Foundation
import Observation

@MainActor
@Observable
final class RealtimeCoordinator: RealtimeEventHandler {
    let chatStore: ChatStore
    let messageStore: MessageStore
    let realtimeService: RealtimeService
    let notificationService: NotificationService

    private var scheduledChatsRefreshTask: Task<Void, Never>?
    private var scheduledMessagesRefreshTasks: [String: Task<Void, Never>] = [:]
    /// Chats with a new incoming message awaiting a notification, processed once
    /// the next debounced chats refresh lands (so we read a fresh `preview`).
    private var pendingNotificationChatIDs: Set<String> = []
    /// The last message ID we notified for, per chat, to avoid duplicate banners.
    private var lastNotifiedMessageIDByChatID: [String: String] = [:]

    var selectedChatID: String? {
        didSet {
            chatStore.selectedChatID = selectedChatID
            // Only the open chat keeps full message history in memory.
            messageStore.retainMessages(forChatID: selectedChatID)
        }
    }

    init(chatStore: ChatStore, messageStore: MessageStore, realtimeService: RealtimeService, notificationService: NotificationService) {
        self.chatStore = chatStore
        self.messageStore = messageStore
        self.realtimeService = realtimeService
        self.notificationService = notificationService
        realtimeService.eventHandler = self
    }

    func updateAccessToken(_ accessToken: String) async {
        if accessToken == APIClient.accessToken { return }

        APIClient.accessToken = accessToken

        if accessToken.isEmpty {
            realtimeService.stop()
            selectedChatID = nil
            chatStore.clearState()
            messageStore.reset()
            pendingNotificationChatIDs.removeAll()
            lastNotifiedMessageIDByChatID.removeAll()
            return
        }

        await chatStore.loadChats()
        realtimeService.start()
    }

    func refreshAfterMessageMutation(chatID: String) async {
        async let chatsRefresh: Void = chatStore.loadChats()
        async let messagesRefresh: [Message] = messageStore.loadMessages(for: chatID)
        _ = await (chatsRefresh, messagesRefresh)
    }

    func setSelectedChatID(_ chatID: String?) {
        selectedChatID = chatID
    }

    // MARK: - RealtimeEventHandler

    nonisolated func realtimeDidUpsertChat(chatID: String?) {
        Task { @MainActor in
            scheduleChatsRefresh()
        }
    }

    nonisolated func realtimeDidDeleteChat(chatID: String?) {
        Task { @MainActor in
            if let chatID {
                chatStore.removeChatLocally(chatID)
            } else {
                scheduleChatsRefresh()
            }
        }
    }

    nonisolated func realtimeDidUpsertMessage(chatID: String?) {
        Task { @MainActor in
            // The chats refresh keeps the sidebar current (preview, unread, order).
            scheduleChatsRefresh()

            if let chatID, chatID == selectedChatID {
                // Open chat: refresh its messages so the timeline updates live.
                scheduleMessagesRefresh(chatID: chatID)
            } else if let chatID {
                // Background chat: notify from the refreshed preview — no need to
                // pull (and retain) the chat's full message history.
                pendingNotificationChatIDs.insert(chatID)
            }
        }
    }

    nonisolated func realtimeDidDeleteMessage(chatID: String?) {
        Task { @MainActor in
            scheduleChatsRefresh()
            if let chatID, chatID == selectedChatID {
                scheduleMessagesRefresh(chatID: chatID)
            }
        }
    }

    nonisolated func realtimeDidUpdateReceipt(chatID: String?, entries: [[String: String]]?) {
        Task { @MainActor in
            // Read-receipts only drive the "Read" indicator for the open chat, which
            // reads `lastReadByOtherSortKeyByChatID` directly — no message reload needed.
            guard let chatID, chatID == selectedChatID,
                  let entry = entries?.first,
                  let readKey = entry["lastReadByOtherSortKey"] else { return }
            messageStore.lastReadByOtherSortKeyByChatID[chatID] = readKey
        }
    }

    nonisolated func realtimeDidReceiveError(_ message: String) {
        Task { @MainActor in
            messageStore.messagesError = message
        }
    }

    // MARK: - Debounce

    private func scheduleChatsRefresh() {
        scheduledChatsRefreshTask?.cancel()
        scheduledChatsRefreshTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch { return }

            guard !Task.isCancelled else { return }
            await self.chatStore.loadChats()
            await self.processPendingNotifications()
        }
    }

    private func scheduleMessagesRefresh(chatID: String) {
        scheduledMessagesRefreshTasks[chatID]?.cancel()
        scheduledMessagesRefreshTasks[chatID] = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch { return }

            guard !Task.isCancelled else { return }
            await self.messageStore.loadMessages(for: chatID)

            if !Task.isCancelled {
                self.scheduledMessagesRefreshTasks[chatID] = nil
            }
        }
    }

    // MARK: - Notifications

    private func processPendingNotifications() async {
        let chatIDs = pendingNotificationChatIDs
        pendingNotificationChatIDs.removeAll()
        guard !chatIDs.isEmpty else { return }

        await chatStore.ensureLowPriorityIDsLoaded()
        for chatID in chatIDs {
            notifyFromPreview(chatID: chatID)
        }
    }

    /// Posts a notification for a background chat using its server-provided
    /// `preview` (the latest message), so we never load full history just to notify.
    private func notifyFromPreview(chatID: String) {
        guard let chat = chatStore.chat(byID: chatID) else { return }
        guard chat.isMuted != true, chatStore.isPrimaryInboxChat(chat) else { return }
        guard let preview = chat.preview else { return }
        guard preview.id != lastNotifiedMessageIDByChatID[chatID] else { return }
        // Skip our own messages, membership events, and reactions.
        guard !preview.isOutgoing(in: chat), !preview.isMembershipEvent, !preview.isReaction else { return }
        // Skip stale messages (older than 60s) to avoid notifying for backfilled history.
        guard Date().timeIntervalSince(preview.timestamp) <= 60 else { return }

        lastNotifiedMessageIDByChatID[chatID] = preview.id
        notificationService.postNewMessageNotification(message: preview, chatTitle: chat.displayTitle)
    }
}
