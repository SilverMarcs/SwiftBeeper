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
    private var lastLoadedInboxFilter: InboxFilter?
    private var chatsByID: [String: Chat] = [:]

    var displayedChats: [Chat] {
        if searchQuery.isBlank {
            return chats
        }
        return searchResults ?? chats
    }

    var selectedChat: Chat? {
        guard let selectedChatID else { return nil }
        return chatsByID[selectedChatID]
    }

    func chat(byID chatID: String) -> Chat? {
        chatsByID[chatID]
    }

    private struct ChatListState {
        var chats: [Chat]
        var selectedChatID: String?
        var chatsCursor: String?
        var hasMoreChats: Bool
        var lowPriorityChatIDs: Set<String>
        var lastLoadedInboxFilter: InboxFilter?
        var chatsError: String?

        static let empty = ChatListState(
            chats: [],
            selectedChatID: nil,
            chatsCursor: nil,
            hasMoreChats: false,
            lowPriorityChatIDs: [],
            lastLoadedInboxFilter: nil,
            chatsError: nil
        )
    }

    private var chatListState: ChatListState {
        get {
            ChatListState(
                chats: chats,
                selectedChatID: selectedChatID,
                chatsCursor: chatsCursor,
                hasMoreChats: hasMoreChats,
                lowPriorityChatIDs: lowPriorityChatIDs,
                lastLoadedInboxFilter: lastLoadedInboxFilter,
                chatsError: chatsError
            )
        }
        set {
            setChats(newValue.chats)
            selectedChatID = newValue.selectedChatID
            chatsCursor = newValue.chatsCursor
            hasMoreChats = newValue.hasMoreChats
            lowPriorityChatIDs = newValue.lowPriorityChatIDs
            lastLoadedInboxFilter = newValue.lastLoadedInboxFilter
            chatsError = newValue.chatsError
        }
    }

    private func setChats(_ newChats: [Chat]) {
        chats = newChats
        chatsByID = Dictionary(newChats.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    func isPrimaryInboxChat(_ chat: Chat) -> Bool {
        !lowPriorityChatIDs.contains(chat.id) && chat.isArchived != true
    }

    /// Ensures `lowPriorityChatIDs` are loaded (fetches them if empty).
    func ensureLowPriorityIDsLoaded() async {
        guard lowPriorityChatIDs.isEmpty else { return }
        lowPriorityChatIDs = (try? await APIClient.listLowPriorityChatIDs()) ?? []
    }

    private func mergedChatsPreservingExistingContext(
        refreshedChats: [Chat],
        existingChats: [Chat],
        shouldPreserveExistingChats: Bool
    ) -> [Chat] {
        guard shouldPreserveExistingChats else { return refreshedChats }

        let refreshedIDs = Set(refreshedChats.map(\.id))
        let preservedExistingChats = existingChats.filter { !refreshedIDs.contains($0.id) }
        return refreshedChats + preservedExistingChats
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
                inbox: selectedInboxFilter.rawValue
            )
            searchResults = response.items
        } catch {
            searchResults = []
        }
        isSearching = false
    }

    func loadChatDetail(for chatID: String) async {
        guard !APIClient.accessToken.isEmpty else { return }

        do {
            let detail = try await APIClient.getChat(chatID: chatID)
            if let index = chats.firstIndex(where: { $0.id == chatID }) {
                let merged = chats[index].merging(detail: detail)
                chats[index] = merged
                chatsByID[chatID] = merged
            }
        } catch {
            // Non-critical; we still have list data
        }
    }

    func clearState() {
        chatListState = .empty
    }

    func loadChats() async {
        guard !APIClient.accessToken.isEmpty else {
            chatListState = .empty
            return
        }

        let snapshot = chatListState
        let shouldPreserveExistingChats = lastLoadedInboxFilter == selectedInboxFilter

        isLoadingChats = true
        defer { isLoadingChats = false }

        do {
            let refreshedChats: [Chat]
            let refreshedCursor: String?
            let refreshedHasMoreChats: Bool

            if selectedInboxFilter == .primary {
                async let chatsResponse = APIClient.listChats()
                async let lowPriorityIDs = (try? APIClient.listLowPriorityChatIDs()) ?? []

                let response = try await chatsResponse
                lowPriorityChatIDs = await lowPriorityIDs
                refreshedChats = response.items.filter(isPrimaryInboxChat)
                refreshedCursor = response.oldestCursor
                refreshedHasMoreChats = response.hasMore ?? false
            } else {
                let response = try await APIClient.searchChats(inbox: selectedInboxFilter.rawValue)
                refreshedChats = response.items
                refreshedCursor = response.oldestCursor
                refreshedHasMoreChats = response.hasMore
            }

            setChats(mergedChatsPreservingExistingContext(
                refreshedChats: refreshedChats,
                existingChats: snapshot.chats,
                shouldPreserveExistingChats: shouldPreserveExistingChats
            ))
            chatsCursor = refreshedCursor
            hasMoreChats = refreshedHasMoreChats
            chatsError = nil
            lastLoadedInboxFilter = selectedInboxFilter

            if let existingSelectedChatID = snapshot.selectedChatID, chatsByID[existingSelectedChatID] != nil {
                selectedChatID = existingSelectedChatID
            } else if chatsByID[selectedChatID ?? ""] == nil {
                selectedChatID = chats.first?.id
            }
        } catch {
            chatListState = snapshot
            chatsError = error.localizedDescription
        }
    }

    func loadMoreChats() async {
        guard !APIClient.accessToken.isEmpty else { return }
        guard hasMoreChats, let cursor = chatsCursor else { return }
        guard !isLoadingMoreChats else { return }

        isLoadingMoreChats = true
        defer { isLoadingMoreChats = false }

        do {
            let existingIDs = Set(chats.map(\.id))

            if selectedInboxFilter == .primary {
                let response = try await APIClient.listChats(cursor: cursor, direction: "before")
                let newChats = response.items.filter { !existingIDs.contains($0.id) && isPrimaryInboxChat($0) }
                setChats(chats + newChats)
                chatsCursor = response.oldestCursor
                hasMoreChats = response.hasMore ?? false
            } else {
                let response = try await APIClient.searchChats(
                    inbox: selectedInboxFilter.rawValue,
                    cursor: cursor,
                    direction: "before"
                )
                let newChats = response.items.filter { !existingIDs.contains($0.id) }
                setChats(chats + newChats)
                chatsCursor = response.oldestCursor
                hasMoreChats = response.hasMore
            }
        } catch {
            // Silently fail on pagination errors; the user can scroll again to retry
        }
    }

    // MARK: - Archive / Unarchive

    func archiveChat(_ chatID: String) async {
        guard !APIClient.accessToken.isEmpty else { return }

        do {
            try await APIClient.archiveChat(chatID: chatID, archived: true)
            setChats(chats.filter { $0.id != chatID })
            if selectedChatID == chatID {
                selectedChatID = chats.first?.id
            }
        } catch {
            chatsError = error.localizedDescription
        }
    }

    func unarchiveChat(_ chatID: String) async {
        guard !APIClient.accessToken.isEmpty else { return }

        do {
            try await APIClient.archiveChat(chatID: chatID, archived: false)
            setChats(chats.filter { $0.id != chatID })
            if selectedChatID == chatID {
                selectedChatID = chats.first?.id
            }
        } catch {
            chatsError = error.localizedDescription
        }
    }

    // MARK: - Mute / Unmute

    func muteChat(_ chatID: String) async {
        guard !APIClient.accessToken.isEmpty else { return }

        do {
            try await APIClient.muteChat(chatID: chatID, muted: true)
            await loadChats()
        } catch {
            chatsError = error.localizedDescription
        }
    }

    func unmuteChat(_ chatID: String) async {
        guard !APIClient.accessToken.isEmpty else { return }

        do {
            try await APIClient.muteChat(chatID: chatID, muted: false)
            await loadChats()
        } catch {
            chatsError = error.localizedDescription
        }
    }

    // MARK: - Mark as Read

    func markChatAsRead(_ chatID: String) async {
        guard !APIClient.accessToken.isEmpty else { return }

        do {
            try await APIClient.markChatAsRead(chatID: chatID)
            await loadChats()
        } catch {
            chatsError = error.localizedDescription
        }
    }
}
