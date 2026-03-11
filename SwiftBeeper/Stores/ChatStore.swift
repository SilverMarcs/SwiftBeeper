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

@MainActor
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
    }

    var displayedChats: [Chat] {
        if searchQuery.isBlank {
            return chats
        }
        return searchResults ?? chats
    }

    var selectedChat: Chat? {
        guard let selectedChatID else { return nil }
        return chats.first(where: { $0.id == selectedChatID })
    }

    private var activeInboxSearchFilter: String? {
        selectedInboxFilter == .primary ? InboxFilter.primary.rawValue : selectedInboxFilter.rawValue
    }

    private func isPrimaryInboxChat(_ chat: Chat) -> Bool {
        !lowPriorityChatIDs.contains(chat.id) && chat.isArchived != true
    }

    func searchChats() async {
        let trimmed = searchQuery.trimmed
        guard !trimmed.isEmpty else {
            searchResults = nil
            isSearching = false
            return
        }

        isSearching = true
        do {
            let response = try await APIClient.searchChats(
                query: trimmed,
                inbox: activeInboxSearchFilter,
                accessToken: currentAccessToken
            )
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
            realtimeService.selectedChatID = nil
            chats = []
            lowPriorityChatIDs = []
            messageStore.reset()
            selectedChatID = nil
            chatsError = nil
            chatsCursor = nil
            hasMoreChats = false
            return
        }

        await loadChats()
        realtimeService.start(accessToken: accessToken)
    }

    func loadChats() async {
        guard !currentAccessToken.isEmpty else {
            chats = []
            lowPriorityChatIDs = []
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
                chats = response.items.filter(isPrimaryInboxChat)
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
                let newChats = response.items.filter { !existingIDs.contains($0.id) && isPrimaryInboxChat($0) }
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

    // MARK: - Message Mutations

    func refreshAfterMessageMutation(chatID: String) async {
        async let chatsRefresh: Void = loadChats()
        async let messagesRefresh: Void = messageStore.loadMessages(for: chatID)
        _ = await (chatsRefresh, messagesRefresh)
    }
}
