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
    /// Snapshot of preview sortKeys before a chat-list refresh, used to detect
    /// which chats received genuinely new messages for notification purposes.
    private var lastKnownPreviewKeys: [String: String] = [:]

    var selectedChatID: String? {
        didSet {
            if oldValue != selectedChatID, let old = oldValue {
                evictMessagesIfNotSelected(chatID: old)
            }
            chatStore.selectedChatID = selectedChatID
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
            lastKnownPreviewKeys = [:]
            return
        }

        await chatStore.loadChats()
        await chatStore.ensureLowPriorityIDsLoaded()
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

    private func evictMessagesIfNotSelected(chatID: String) {
        guard chatID != selectedChatID else { return }
        messageStore.evictMessages(for: chatID)
    }

    // MARK: - RealtimeEventHandler

    nonisolated func realtimeDidUpsertChat(chatID: String?) {
        Task { @MainActor in scheduleChatsRefresh() }
    }

    nonisolated func realtimeDidDeleteChat(chatID: String?) {
        Task { @MainActor in scheduleChatsRefresh() }
    }

    nonisolated func realtimeDidUpsertMessage(chatID: String?) {
        Task { @MainActor in
            // Refresh sidebar (chat list) only — preview/unread counts update from the API.
            scheduleChatsRefreshAndNotify(chatID: chatID)
            // If this is the open chat, also refresh messages to keep the timeline live.
            if let chatID, chatID == selectedChatID {
                scheduleMessagesRefresh(chatID: chatID)
            }
        }
    }

    nonisolated func realtimeDidDeleteMessage(chatID: String?) {
        Task { @MainActor in
            if let chatID, chatID == selectedChatID {
                scheduleMessagesRefresh(chatID: chatID)
            }
        }
    }

    nonisolated func realtimeDidUpdateReceipt(chatID: String?, entries: [[String: String]]?) {
        Task { @MainActor in
            if let chatID, let entries, let entry = entries.first,
               let readKey = entry["lastReadByOtherSortKey"] {
                messageStore.lastReadByOtherSortKeyByChatID[chatID] = readKey
            }
            if let chatID, chatID == selectedChatID {
                scheduleMessagesRefresh(chatID: chatID)
            }
        }
    }

    nonisolated func realtimeDidReceiveError(_ message: String) {
        Task { @MainActor in
            messageStore.messagesError = message
        }
    }

    // MARK: - Debounced refreshes

    private func scheduleChatsRefresh() {
        scheduledChatsRefreshTask?.cancel()
        scheduledChatsRefreshTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled else { return }
            await self.chatStore.loadChats()
        }
    }

    /// Refreshes chats and then posts a notification if the target chat received
    /// a genuinely new incoming message (detected by preview sortKey change).
    private func scheduleChatsRefreshAndNotify(chatID: String?) {
        scheduledChatsRefreshTask?.cancel()
        scheduledChatsRefreshTask = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled else { return }

            let previousKey = chatID.flatMap { self.lastKnownPreviewKeys[$0] }
            await self.chatStore.loadChats()

            guard !Task.isCancelled, let chatID else { return }

            // Update preview-key snapshot for all chats
            for chat in self.chatStore.chats {
                if let previewSort = chat.preview?.sortKey {
                    self.lastKnownPreviewKeys[chat.id] = previewSort
                }
            }

            // Post notification only if this chat got a new preview message
            guard let chat = self.chatStore.chat(byID: chatID),
                  let currentKey = chat.preview?.sortKey,
                  currentKey != previousKey else { return }

            // Skip muted, non-primary, and outgoing previews
            guard chat.isMuted != true,
                  self.chatStore.isPrimaryInboxChat(chat),
                  let preview = chat.preview,
                  !preview.isOutgoing(in: chat),
                  !preview.isMembershipEvent else { return }

            // Skip reaction previews unless targeting own message
            if preview.isReaction,
               !self.messageStore.isReactionToOwnMessage(preview, in: chat) { return }

            // Only notify for recent messages (not history loaded after reconnect)
            if Date().timeIntervalSince(preview.timestamp) > 60 { return }

            self.notificationService.postNewMessageNotification(
                message: preview,
                chatTitle: chat.displayTitle
            )
        }
    }

    private func scheduleMessagesRefresh(chatID: String) {
        scheduledMessagesRefreshTasks[chatID]?.cancel()
        scheduledMessagesRefreshTasks[chatID] = Task { [weak self] in
            guard let self else { return }
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard !Task.isCancelled else { return }
            await self.messageStore.loadMessages(for: chatID)
            if !Task.isCancelled {
                self.scheduledMessagesRefreshTasks[chatID] = nil
            }
        }
    }
}
