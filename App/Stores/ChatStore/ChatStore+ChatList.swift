import Foundation

/// The sidebar: loading and paging the chat list, search, live chat updates,
/// and per-chat actions.
extension ChatStore {
    var displayedChats: [Chat] {
        searchQuery.isBlank ? chats : (searchResults ?? chats)
    }

    var availableServiceFilters: [ChatFilter] {
        guard !connectedAccounts.isEmpty else {
            return [
                .service(serviceID: "whatsapp", name: "WhatsApp"),
                .service(serviceID: "telegram", name: "Telegram"),
                .service(serviceID: "facebookgo", name: "Messenger"),
                .service(serviceID: "instagramgo", name: "Instagram"),
                .service(serviceID: "signal", name: "Signal"),
                .service(serviceID: "discordgo", name: "Discord"),
                .service(serviceID: "slackgo", name: "Slack"),
                .service(serviceID: "linkedin", name: "LinkedIn"),
                .service(serviceID: "gmessages", name: "Google Messages"),
                .service(serviceID: "gvoice", name: "Google Voice"),
                .service(serviceID: "twitter", name: "Twitter/X"),
                .service(serviceID: "imessage", name: "iMessage")
            ]
        }

        var seen: Set<String> = []
        return connectedAccounts.compactMap { account in
            guard seen.insert(account.accountID).inserted else { return nil }
            return .service(serviceID: account.accountID, name: account.network)
        }
    }

    /// The inbox the selected filter lists; a service filter lists its primary inbox.
    private var selectedInboxFilter: InboxFilter {
        switch selectedFilter {
        case .inbox(let inbox): inbox
        case .service: .primary
        }
    }

    /// Which chat to fall back to when the current selection becomes invalid.
    /// macOS and iPad auto-select the first chat; iPhone stays manual (nil).
    private var autoSelectedChatID: String? {
        Device.isIPhone ? nil : chats.first?.id
    }

    // MARK: - Loading

    func loadChats() async {
        guard isSignedIn else {
            resetChatList()
            return
        }

        let requestedFilter = selectedFilter
        let shouldPreserveExistingChats = lastLoadedFilterID == requestedFilter.id
        let session = session

        let requestID = UUID()
        latestChatsRequestID = requestID
        isLoadingChats = true
        defer {
            if latestChatsRequestID == requestID {
                isLoadingChats = false
                loadPendingNotificationChat()
            }
        }

        do {
            let response = try await APIClient.listChats(
                inbox: selectedInboxFilter.rawValue,
                accountIDs: requestedFilter.accountIDs
            )
            guard latestChatsRequestID == requestID, selectedFilter.id == requestedFilter.id,
                  self.session == session, !Task.isCancelled else { return }
            if !shouldPreserveExistingChats { chatWindowSize = Self.chatPageSize }

            // A refresh of the same list keeps the older pages already scrolled in.
            var refreshedChats = response.items
            let preservesOlderPages = shouldPreserveExistingChats && chats.count > refreshedChats.count
            if shouldPreserveExistingChats {
                let refreshedIDs = Set(refreshedChats.map(\.id))
                refreshedChats += chats.filter { !refreshedIDs.contains($0.id) }
            }
            setChats(Array(refreshedChats.prefix(chatWindowSize)))
            if !preservesOlderPages {
                hasMoreChats = response.hasMore
            }
            chatsError = nil
            lastLoadedFilterID = requestedFilter.id

            // Preserve the selection while refreshing; choose the first chat
            // on macOS/iPad when the current selection is no longer present.
            if selectedChat == nil {
                selectedChatID = autoSelectedChatID
            }
        } catch {
            guard latestChatsRequestID == requestID, selectedFilter.id == requestedFilter.id,
                  self.session == session, !Task.isCancelled,
                  !isCancellationLikeError(error) else { return }
            chatsError = error.localizedDescription
        }
    }

    func loadMoreChats() async {
        guard isSignedIn, !isLoadingChats, !isLoadingMoreChats,
              searchQuery.isBlank, chatsError == nil else { return }
        guard hasMoreChats, let lastChat = chats.last else { return }

        let requestedFilter = selectedFilter
        let requestID = latestChatsRequestID
        let session = session

        isLoadingMoreChats = true
        defer { isLoadingMoreChats = false }

        do {
            // Page from the last chat shown, which live updates may have changed.
            let response = try await APIClient.listChats(
                inbox: selectedInboxFilter.rawValue,
                accountIDs: requestedFilter.accountIDs,
                before: lastChat
            )
            guard selectedFilter.id == requestedFilter.id,
                  latestChatsRequestID == requestID, !isLoadingChats,
                  self.session == session,
                  searchQuery.isBlank, !Task.isCancelled else { return }
            let existingIDs = Set(chats.map(\.id))
            let newChats = response.items.filter { !existingIDs.contains($0.id) }
            setChats(chats + newChats)
            chatWindowSize = max(chatWindowSize + Self.chatPageSize, chats.count)
            hasMoreChats = response.hasMore && !response.items.isEmpty
        } catch {
            // Scrolling down again retries the same local page.
        }
    }

    // MARK: - Search

    func submitSearch() {
        let query = searchQuery.trimmed
        guard !query.isEmpty else {
            resetSearch()
            return
        }

        searchTask?.cancel()
        let requestID = UUID()
        latestSearchRequestID = requestID
        searchResults = []
        isSearching = true

        let filter = selectedFilter
        let inbox = selectedInboxFilter
        searchTask = Task { [weak self] in
            await self?.performSearch(query: query, filter: filter, inbox: inbox, requestID: requestID)
        }
    }

    private func performSearch(query: String, filter: ChatFilter, inbox: InboxFilter, requestID: UUID) async {
        defer {
            if latestSearchRequestID == requestID {
                isSearching = false
                searchTask = nil
                latestSearchRequestID = nil
            }
        }

        do {
            let response = try await APIClient.searchChats(
                query: query,
                inbox: inbox.rawValue,
                accountIDs: filter.accountIDs
            )
            guard !Task.isCancelled,
                  latestSearchRequestID == requestID,
                  selectedFilter.id == filter.id,
                  searchQuery.trimmed == query else { return }
            searchResults = response.items
        } catch {
            guard !Task.isCancelled, latestSearchRequestID == requestID else { return }
            searchResults = []
        }
    }

    func resetSearch() {
        searchTask?.cancel()
        searchTask = nil
        latestSearchRequestID = nil
        searchResults = nil
        isSearching = false
    }

    // MARK: - Chat actions

    func archiveChat(_ chatID: String) async { await setArchived(chatID, archived: true) }
    func unarchiveChat(_ chatID: String) async { await setArchived(chatID, archived: false) }

    private func setArchived(_ chatID: String, archived: Bool) async {
        do {
            try await APIClient.archiveChat(chatID: chatID, archived: archived)
            removeChatLocally(chatID)
        } catch {
            chatsError = error.localizedDescription
            return
        }
        do { try await notificationService.syncNotificationPreferences() }
        catch { chatsError = "Archive setting saved, but notification preferences could not be updated. Reopen Relay to retry." }
    }

    func muteChat(_ chatID: String) async { await setChatMuted(chatID, muted: true) }
    func unmuteChat(_ chatID: String) async { await setChatMuted(chatID, muted: false) }

    private func setChatMuted(_ chatID: String, muted: Bool) async {
        let previous = chat(byID: chatID)
        updateChat(chatID) { $0.isMuted = muted }

        do {
            try await APIClient.muteChat(chatID: chatID, muted: muted)
        } catch {
            if let previous { updateChat(chatID) { $0 = previous } }
            chatsError = error.localizedDescription
            return
        }
        do { try await notificationService.syncNotificationPreferences() }
        catch { chatsError = "Mute setting saved, but the notification filter could not be updated. Reopen Relay to retry." }
    }

    func markChatAsRead(_ chatID: String) async {
        notificationService.clearDeliveredNotifications(for: chatID)
        let previous = chat(byID: chatID)
        updateChat(chatID) { $0.unreadCount = 0 }

        do {
            try await APIClient.markChatAsRead(chatID: chatID)
        } catch {
            if let previous { updateChat(chatID) { $0 = previous } }
            chatsError = error.localizedDescription
        }
    }

    // MARK: - Live updates

    /// Applies a `chat.upserted` summary to the sidebar without a full list
    /// reload. The summary includes filter membership and ordering.
    func applyChatUpsert(_ incoming: Chat) {
        if pendingNotificationChatID == incoming.id {
            let filter = ChatFilter.inbox(incoming.isArchived == true ? .archive : .primary)
            if selectedFilter != filter { selectedFilter = filter }
            chatWindowSize = max(chatWindowSize, chats.count + 1)
        }
        updateSelectedChat(incoming)
        // Keep an in-flight search view consistent if it holds this chat.
        if var results = searchResults,
           let index = results.firstIndex(where: { $0.id == incoming.id }) {
            results[index] = incoming
            searchResults = results
        }

        guard chatBelongsToCurrentFilter(incoming) else {
            removeChatLocally(incoming.id)
            return
        }

        var updated = chats
        if let index = updated.firstIndex(where: { $0.id == incoming.id }) {
            updated[index] = incoming
        } else {
            updated.append(incoming)
        }
        // The core orders chats by activity (sorting_timestamp DESC); mirror
        // that so a freshly-active chat moves to the top of the sidebar.
        updated.sort {
            let left = $0.lastActivity ?? .distantPast, right = $1.lastActivity ?? .distantPast
            return left == right ? $0.id < $1.id : left > right
        }
        if updated.count > chatWindowSize { hasMoreChats = true }
        setChats(Array(updated.prefix(chatWindowSize)))
    }

    /// Removes a chat from the sidebar and search results, moving the
    /// selection on if it was open.
    func removeChatLocally(_ chatID: String) {
        setChats(chats.filter { $0.id != chatID })
        if var results = searchResults {
            results.removeAll { $0.id == chatID }
            searchResults = results
        }
        if selectedChatID == chatID {
            selectedChatID = autoSelectedChatID
        }
    }

    /// Mirrors the core's inbox and exact account filtering for chat events.
    private func chatBelongsToCurrentFilter(_ chat: Chat) -> Bool {
        if case .service(let accountID, _) = selectedFilter,
           chat.accountID != accountID {
            return false
        }
        switch selectedInboxFilter {
        case .primary: return chat.isArchived != true
        case .archive: return chat.isArchived == true
        case .unread: return chat.unreadCount > 0 || chat.isMarkedUnread == true
        }
    }

    // MARK: - Storage

    private func setChats(_ newChats: [Chat]) {
        if let selected = newChats.first(where: { $0.id == selectedChatID }) {
            updateSelectedChat(selected)
        }
        // Skip identical commits: a database reload often equals the
        // event-applied sidebar state.
        guard newChats != chats else { return }
        chats = newChats
        resolveNotificationChat()
    }

    private func updateSelectedChat(_ incoming: Chat) {
        guard incoming.id == selectedChatID, incoming != selectedChat else { return }
        selectedChat = incoming
    }

    /// Applies an optimistic change to every copy of a chat.
    private func updateChat(_ chatID: String, _ mutate: (inout Chat) -> Void) {
        if var selected = selectedChat, selected.id == chatID {
            mutate(&selected)
            selectedChat = selected
        }
        if let index = chats.firstIndex(where: { $0.id == chatID }) {
            mutate(&chats[index])
        }
        if var results = searchResults,
           let searchIndex = results.firstIndex(where: { $0.id == chatID }) {
            mutate(&results[searchIndex])
            searchResults = results
        }
    }

    /// Empties the sidebar, which also clears the selection and open timeline.
    func resetChatList() {
        setChats([])
        selectedChatID = nil
        hasMoreChats = false
        lastLoadedFilterID = nil
        chatWindowSize = Self.chatPageSize
        chatsError = nil
    }
}
