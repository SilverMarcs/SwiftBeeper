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
    private(set) var chatsErrorIsAuth: Bool = false
    private(set) var isRecoveringAuth: Bool = false
    var selectedChatID: String?
    var selectedInboxFilter: InboxFilter = .primary
    var searchQuery: String = ""
    var searchResults: [Chat]?
    var isSearching = false
    private var hasCompletedInitialLoad = false
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
        return chat(byID: selectedChatID)
    }

    func chat(byID chatID: String) -> Chat? {
        chatsByID[chatID] ?? searchResults?.first(where: { $0.id == chatID })
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
        let existingByID = Dictionary(existingChats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // The list endpoint omits detail-only fields like `participants`. Merge each
        // refreshed row into the existing one so hydrated data (avatars, etc.) survives.
        let mergedRefreshed = refreshedChats.map { refreshed in
            existingByID[refreshed.id]?.merging(detail: refreshed) ?? refreshed
        }

        guard shouldPreserveExistingChats else { return mergedRefreshed }

        let refreshedIDs = Set(refreshedChats.map(\.id))
        let preservedExistingChats = existingChats.filter { !refreshedIDs.contains($0.id) }
        return mergedRefreshed + preservedExistingChats
    }

    func searchChats() async {
        let trimmed = searchQuery.trimmed
        guard !trimmed.isEmpty else {
            searchResults = nil
            isSearching = false
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            let response = try await APIClient.searchChats(
                query: trimmed,
                inbox: selectedInboxFilter.rawValue
            )
            searchResults = response.items

            // Hydrate metadata (preview, last activity) for results not already in the main list.
            for item in response.items where chatsByID[item.id] == nil {
                if Task.isCancelled { return }
                await loadChatDetail(for: item.id)
            }
        } catch {
            searchResults = []
        }
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
            if let searchIndex = searchResults?.firstIndex(where: { $0.id == chatID }),
               var updated = searchResults {
                updated[searchIndex] = updated[searchIndex].merging(detail: detail)
                searchResults = updated
            }
        } catch {
            // Non-critical; we still have list data
        }
    }

    func clearState() {
        chatListState = .empty
        hasCompletedInitialLoad = false
    }

    func loadChats() async {
        await performLoadChats(retriesRemaining: 1)
    }

    private func performLoadChats(retriesRemaining: Int) async {
        guard !APIClient.accessToken.isEmpty else {
            chatListState = .empty
            return
        }

        let snapshot = chatListState
        let shouldPreserveExistingChats = lastLoadedInboxFilter == selectedInboxFilter
        let tokenAtStart = APIClient.accessToken

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
            chatsErrorIsAuth = false
            lastLoadedInboxFilter = selectedInboxFilter

            // Auto-select first chat on initial load only. Subsequent
            // background refreshes must not hijack the user's selection.
            if !hasCompletedInitialLoad, selectedChatID == nil {
                selectedChatID = chats.first?.id
                hasCompletedInitialLoad = true
            } else if hasCompletedInitialLoad, selectedChatID == nil {
                selectedChatID = snapshot.selectedChatID
            }

            // If the selected chat disappeared from the list, fall back to first.
            if let sid = selectedChatID, chatsByID[sid] == nil {
                selectedChatID = chats.first?.id
            }
        } catch {
            // sendRaw retried internally with a fresh token but still saw 401
            // (server hadn't yet activated the new token). The token has since
            // been minted — try once more before surfacing the error.
            if retriesRemaining > 0,
               case APIError.http(401, _) = error,
               APIClient.accessToken != tokenAtStart {
                await performLoadChats(retriesRemaining: retriesRemaining - 1)
                return
            }
            // The outer `.task(id: accessToken)` cancels in-flight loads when the
            // token rotates after a refresh. Don't surface that as a user-visible
            // error — the next .task firing will reload with the new token.
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
            chatListState = snapshot
            chatsError = error.localizedDescription
            if case APIError.http(401, _) = error {
                chatsErrorIsAuth = true
            } else {
                chatsErrorIsAuth = false
            }
        }
    }

    func recoverAuthAndReload() async {
        guard !isRecoveringAuth, let refresher = APIClient.tokenRefresher else { return }
        isRecoveringAuth = true
        defer { isRecoveringAuth = false }
        do {
            _ = try await refresher()
        } catch {
            chatsErrorIsAuth = false
            chatsError = "Session expired. Please sign in again."
            return
        }
        await loadChats()
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
        await setChatMuted(chatID, muted: true)
    }

    func unmuteChat(_ chatID: String) async {
        await setChatMuted(chatID, muted: false)
    }

    private func setChatMuted(_ chatID: String, muted: Bool) async {
        guard !APIClient.accessToken.isEmpty else { return }

        let previous = chatsByID[chatID]
        updateChat(chatID) { $0.with(isMuted: muted) }

        do {
            try await APIClient.muteChat(chatID: chatID, muted: muted)
        } catch {
            if let previous { updateChat(chatID) { _ in previous } }
            chatsError = error.localizedDescription
        }
    }

    // MARK: - Mark as Read

    func markChatAsRead(_ chatID: String) async {
        guard !APIClient.accessToken.isEmpty else { return }

        let previous = chatsByID[chatID]
        updateChat(chatID) { $0.with(unreadCount: 0) }

        do {
            try await APIClient.markChatAsRead(chatID: chatID)
        } catch {
            if let previous { updateChat(chatID) { _ in previous } }
            chatsError = error.localizedDescription
        }
    }

    private func updateChat(_ chatID: String, transform: (Chat) -> Chat) {
        if let index = chats.firstIndex(where: { $0.id == chatID }) {
            let updated = transform(chats[index])
            chats[index] = updated
            chatsByID[chatID] = updated
        }
        if let searchIndex = searchResults?.firstIndex(where: { $0.id == chatID }),
           var updated = searchResults {
            updated[searchIndex] = transform(updated[searchIndex])
            searchResults = updated
        }
    }
}
