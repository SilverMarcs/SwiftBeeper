import Foundation
import Observation

enum InboxFilter: String, CaseIterable {
    case primary
    case lowPriority = "low-priority"
    case archive

    var label: String {
        switch self {
        case .primary: "Primary"
        case .lowPriority: "Low Priority"
        case .archive: "Archive"
        }
    }

    var systemImage: String {
        switch self {
        case .primary: "tray.full"
        case .lowPriority: "tray"
        case .archive: "archivebox"
        }
    }
}

@Observable
final class ChatStore {
    private(set) var chats: [Chat] = []
    private(set) var hasMoreChats = false
    private(set) var isLoadingMoreChats = false
    private(set) var isLoadingChats = false
    private(set) var chatsError: String?
    var selectedChatID: String?
    var selectedInboxFilter: InboxFilter = .primary
    var searchQuery: String = ""
    var searchResults: [Chat]?
    var isSearching = false
    private var lowPriorityChatIDs: Set<String> = []
    private var chatsCursor: String?
    private(set) var currentAccessToken = ""

    let messageStore = MessageStore()
    let realtimeService = RealtimeService()

    init() {
        let messageStore = self.messageStore
        let realtimeService = self.realtimeService
        realtimeService.onRefreshChats = { [weak self] in
            await self?.loadChats()
        }
        realtimeService.onRefreshMessages = { [weak messageStore] chatID in
            await messageStore?.loadMessages(for: chatID)
        }
        realtimeService.onRealtimeError = { error in
            Task { @MainActor [weak messageStore] in
                messageStore?.messagesError = error
            }
        }
        realtimeService.onChatsUpserted = { [weak self] chats in
            await MainActor.run { self?.upsertChats(chats) }
        }
        realtimeService.onChatsDeleted = { [weak self] ids in
            await MainActor.run { self?.deleteChats(ids: ids) }
        }
        realtimeService.onMessagesUpserted = { [weak messageStore] chatID, messages in
            await MainActor.run { messageStore?.upsertMessages(messages, for: chatID) }
        }
        realtimeService.onMessagesDeleted = { [weak messageStore] chatID, ids in
            await MainActor.run { messageStore?.deleteMessages(ids: ids, from: chatID) }
        }
        realtimeService.loadedMessageChatIDs = { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return [] }
                return Set(self.messageStore.messagesByChatID.keys)
            }
        }
    }

    var displayedChats: [Chat] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return chats
        }
        return searchResults ?? chats
    }

    var selectedChat: Chat? {
        guard let selectedChatID else { return nil }
        return chats.first(where: { $0.id == selectedChatID })
    }

    func searchChats() async {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = nil
            isSearching = false
            return
        }

        isSearching = true
        do {
            let response = try await APIClient.searchChats(query: trimmed, accessToken: currentAccessToken)
            searchResults = response.items
        } catch {
            searchResults = []
        }
        isSearching = false
    }

    func loadChatDetail(for chatID: String) async {
        guard !currentAccessToken.isEmpty else { return }

        do {
            let detail = try await APIClient.getChat(chatID: chatID, accessToken: currentAccessToken)
            if let index = chats.firstIndex(where: { $0.id == chatID }) {
                chats[index] = chats[index].merging(detail: detail)
            }
        } catch {
            // Non-critical; we still have list data
        }
    }

    func updateAccessToken(_ accessToken: String) async {
        if accessToken == currentAccessToken { return }

        currentAccessToken = accessToken
        messageStore.currentAccessToken = accessToken

        if accessToken.isEmpty {
            realtimeService.stop()
            chats = []
            messageStore.reset()
            selectedChatID = nil
            chatsError = nil
            return
        }

        await loadChats()
        realtimeService.start(accessToken: accessToken)
    }

    func loadChats() async {
        guard !currentAccessToken.isEmpty else {
            chats = []
            messageStore.reset()
            selectedChatID = nil
            chatsError = nil
            chatsCursor = nil
            hasMoreChats = false
            return
        }

        isLoadingChats = true
        defer { isLoadingChats = false }

        chatsCursor = nil
        hasMoreChats = false

        do {
            if selectedInboxFilter == .primary {
                async let chatsResponse = APIClient.listChats(accessToken: currentAccessToken)
                async let lowPriorityIDs = (try? APIClient.listLowPriorityChatIDs(accessToken: currentAccessToken)) ?? []

                let response = try await chatsResponse
                lowPriorityChatIDs = await lowPriorityIDs
                chats = response.items.filter { !lowPriorityChatIDs.contains($0.id) }
                chatsCursor = response.oldestCursor
                hasMoreChats = response.hasMore ?? false
            } else {
                let response = try await APIClient.searchChats(inbox: selectedInboxFilter.rawValue, accessToken: currentAccessToken)
                chats = response.items
                chatsCursor = response.oldestCursor
                hasMoreChats = response.hasMore
            }
            chatsError = nil

            if !chats.contains(where: { $0.id == selectedChatID }) {
                selectedChatID = chats.first?.id
            }
        } catch {
            chatsError = error.localizedDescription
            chats = []
            messageStore.reset()
            selectedChatID = nil
            chatsCursor = nil
            hasMoreChats = false
        }
    }

    func loadMoreChats() async {
        guard !currentAccessToken.isEmpty else { return }
        guard hasMoreChats, let cursor = chatsCursor else { return }
        guard !isLoadingMoreChats else { return }

        isLoadingMoreChats = true
        defer { isLoadingMoreChats = false }

        do {
            let existingIDs = Set(chats.map(\.id))

            if selectedInboxFilter == .primary {
                let response = try await APIClient.listChats(cursor: cursor, direction: "before", accessToken: currentAccessToken)
                let newChats = response.items.filter {
                    !existingIDs.contains($0.id) && !lowPriorityChatIDs.contains($0.id)
                }
                chats.append(contentsOf: newChats)
                chatsCursor = response.oldestCursor
                hasMoreChats = response.hasMore ?? false
            } else {
                let response = try await APIClient.searchChats(
                    inbox: selectedInboxFilter.rawValue,
                    cursor: cursor,
                    direction: "before",
                    accessToken: currentAccessToken
                )
                let newChats = response.items.filter { !existingIDs.contains($0.id) }
                chats.append(contentsOf: newChats)
                chatsCursor = response.oldestCursor
                hasMoreChats = response.hasMore
            }
        } catch {
            // Silently fail on pagination errors; the user can scroll again to retry
        }
    }

    // MARK: - Direct upsert / delete (from WebSocket payloads)

    func upsertChats(_ updatedChats: [Chat]) {
        var current = chats
        for chat in updatedChats {
            if selectedInboxFilter == .primary && lowPriorityChatIDs.contains(chat.id) {
                continue
            }
            if let index = current.firstIndex(where: { $0.id == chat.id }) {
                current[index] = current[index].merging(detail: chat)
            } else {
                current.append(chat)
            }
        }
        chats = current.sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
    }

    func deleteChats(ids: [String]) {
        let idsToRemove = Set(ids)
        chats.removeAll { idsToRemove.contains($0.id) }
        if let selectedChatID, idsToRemove.contains(selectedChatID) {
            self.selectedChatID = chats.first?.id
        }
    }

    // MARK: - Archive / Unarchive

    func archiveChat(_ chatID: String) async {
        guard !currentAccessToken.isEmpty else { return }

        do {
            try await APIClient.archiveChat(chatID: chatID, archived: true, accessToken: currentAccessToken)
            chats.removeAll { $0.id == chatID }
            if selectedChatID == chatID {
                selectedChatID = chats.first?.id
            }
        } catch {
            chatsError = error.localizedDescription
        }
    }

    func unarchiveChat(_ chatID: String) async {
        guard !currentAccessToken.isEmpty else { return }

        do {
            try await APIClient.archiveChat(chatID: chatID, archived: false, accessToken: currentAccessToken)
            chats.removeAll { $0.id == chatID }
            if selectedChatID == chatID {
                selectedChatID = chats.first?.id
            }
        } catch {
            chatsError = error.localizedDescription
        }
    }

    // MARK: - Realtime-triggered refresh scheduling (called by MessageStore after send/edit)

    func scheduleRefreshAfterSend(chatID: String) {
        realtimeService.scheduleChatsRefresh()
        realtimeService.scheduleMessagesRefresh(chatID: chatID)
    }
}
