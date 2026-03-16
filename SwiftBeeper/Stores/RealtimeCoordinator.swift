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
                } else if messageStore.messagesByChatID[chatID] != nil {
                    // Non-selected chat we've already loaded: refresh and notify
                    scheduleMessagesRefreshWithNotification(chatID: chatID)
                }
                // Chats we haven't loaded messages for: skip (chat list refresh handles unread badge)
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
            let newMessages = await self.messageStore.loadMessages(for: chatID)

            guard !Task.isCancelled else { return }
            self.scheduledMessagesRefreshTasks[chatID] = nil

            // Post notifications for truly new incoming messages
            let chat = self.chatStore.chat(byID: chatID)
            let isMuted = chat?.isMuted == true
            guard !isMuted, !newMessages.isEmpty else { return }

            let chatTitle = chat?.displayTitle ?? "New Message"
            for message in newMessages {
                // Skip outgoing, reactions, membership events
                if let chat, message.isOutgoing(in: chat) { continue }
                if message.isReaction || message.isMembershipEvent || message.isEmptyDeleted { continue }

                self.notificationService.postNewMessageNotification(
                    message: message,
                    chatTitle: chatTitle
                )
            }
        }
    }
}
