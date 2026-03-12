import Foundation
import Observation

@MainActor
@Observable
final class RealtimeCoordinator: RealtimeEventHandler {
    let chatStore: ChatStore
    let messageStore: MessageStore
    let realtimeService: RealtimeService

    private var scheduledChatsRefreshTask: Task<Void, Never>?
    private var scheduledMessagesRefreshTasks: [String: Task<Void, Never>] = [:]

    var selectedChatID: String? {
        didSet {
            chatStore.selectedChatID = selectedChatID
        }
    }

    init(chatStore: ChatStore, messageStore: MessageStore, realtimeService: RealtimeService) {
        self.chatStore = chatStore
        self.messageStore = messageStore
        self.realtimeService = realtimeService
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
        async let messagesRefresh: Void = messageStore.loadMessages(for: chatID)
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
            if let chatID, chatID == selectedChatID {
                scheduleMessagesRefresh(chatID: chatID)
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

            defer {
                self.scheduledMessagesRefreshTasks[chatID] = nil
            }

            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch { return }

            guard !Task.isCancelled else { return }
            await self.messageStore.loadMessages(for: chatID)
        }
    }
}
