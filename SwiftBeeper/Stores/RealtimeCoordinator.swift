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

    var selectedChatID: String? {
        didSet {
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
            scheduleChatsRefresh()
        }
    }

    nonisolated func realtimeDidUpsertMessage(chatID: String?) {
        Task { @MainActor in
            scheduleChatsRefresh()
            if let chatID {
                if chatID == selectedChatID {
                    // Selected chat: refresh messages and check for new ones to notify
                    scheduleMessagesRefreshWithNotification(chatID: chatID)
                } else {
                    // Any other chat: refresh and notify
                    scheduleMessagesRefreshWithNotification(chatID: chatID)
                }
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
            // Update read-by-other sort key directly from the WS event entry.
            if let chatID, let entries, let entry = entries.first,
               let readKey = entry["lastReadByOtherSortKey"] {
                messageStore.lastReadByOtherSortKeyByChatID[chatID] = readKey
            }
            // Also refresh messages if this is the selected chat to update the UI.
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

    private func scheduleMessagesRefreshWithNotification(chatID: String) {
        scheduledMessagesRefreshTasks[chatID]?.cancel()
        scheduledMessagesRefreshTasks[chatID] = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch { return }

            guard !Task.isCancelled else { return }

            // Track whether this is the first load for this chat
            let isFirstLoad = self.messageStore.messagesByChatID[chatID] == nil
            let newMessages = await self.messageStore.loadMessages(for: chatID)

            guard !Task.isCancelled else { return }
            self.scheduledMessagesRefreshTasks[chatID] = nil

            // For first loads, loadMessages returns [] (by design).
            // Since a realtime event triggered this, the latest message is the new one.
            let messagesToNotify: [Message]
            if isFirstLoad {
                if let latestMessage = self.messageStore.messagesByChatID[chatID]?.last {
                    messagesToNotify = [latestMessage]
                } else {
                    messagesToNotify = []
                }
            } else {
                messagesToNotify = newMessages
            }

            // Post notifications for truly new incoming messages
            await self.chatStore.ensureLowPriorityIDsLoaded()
            guard let chat = self.chatStore.chat(byID: chatID) else { return }
            let isMuted = chat.isMuted == true
            let isPrimary = self.chatStore.isPrimaryInboxChat(chat)
            guard !isMuted, isPrimary, !messagesToNotify.isEmpty else { return }

            let chatTitle = chat.displayTitle
            for message in messagesToNotify {
                // Skip outgoing and membership events. Deletions are allowed through.
                // Reactions are only surfaced when they target one of the user's own messages.
                if message.isOutgoing(in: chat) { continue }
                if message.isMembershipEvent { continue }
                if message.isReaction, !self.messageStore.isReactionToOwnMessage(message, in: chat) { continue }
                // Skip stale messages (older than 60s) to avoid notifying for old chat history
                if Date().timeIntervalSince(message.timestamp) > 60 { continue }

                self.notificationService.postNewMessageNotification(
                    message: message,
                    chatTitle: chatTitle
                )
            }
        }
    }
}
