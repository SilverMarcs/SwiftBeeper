import Foundation

/// The sidebar: loading and paging the chat list, search, live chat updates,
/// and per-chat actions.
extension ChatStore {
    var isSearchActive: Bool { searchQuery.trimmed.count >= 3 }

    var displayedChats: [Chat] {
        guard !isSearchActive else { return searchResults ?? [] }
        let pins = pinnedChats.sorted {
            let left = $0.pinOrder ?? 1, right = $1.pinOrder ?? 1
            return left == right ? $0.id < $1.id : left < right
        }
        let pinnedIDs = Set(pins.map(\.id))
        return pins + chats.filter { !pinnedIDs.contains($0.id) }
    }

    var availableServiceFilters: [ChatFilter] {
        guard !connectedAccounts.isEmpty else {
            return [
                .service(serviceID: "whatsapp", name: "WhatsApp"),
                .service(serviceID: "telegram", name: "Telegram"),
                .service(serviceID: "facebookgo", name: "Facebook"),
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
        Device.isIPhone ? nil : displayedChats.first?.id
    }

    // MARK: - Navigation

    /// Retains a directly opened chat even when its row isn't in the loaded page.
    func openChat(_ chat: Chat) {
        searchQuery = ""
        if selectedFilter == .inbox(.unread) || !chatBelongsToCurrentFilter(chat) {
            selectedFilter = .inbox(chat.isArchived == true ? .archive : .primary)
        }
        selectedChat = chat
        selectedChatID = chat.id
        chatNavigationID = UUID()
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
            pinnedChats = response.pinned ?? []
            setChats(Array(refreshedChats.prefix(chatWindowSize)))
            if let selected = pinnedChats.first(where: { $0.id == selectedChatID }) {
                updateSelectedChat(selected)
            }
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
              !isSearchActive, chatsError == nil else { return }
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
                  !isSearchActive, !Task.isCancelled else { return }
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

    func searchChats() async {
        let query = searchQuery.trimmed
        guard isSignedIn, isSearchActive else {
            resetSearch()
            return
        }

        let requestID = UUID()
        latestSearchRequestID = requestID
        isSearching = false

        let filter = selectedFilter
        let inbox = selectedInboxFilter
        let session = session

        defer {
            if latestSearchRequestID == requestID {
                isSearching = false
                latestSearchRequestID = nil
            }
        }

        do {
            try await Task.sleep(for: .milliseconds(200))
            try Task.checkCancellation()
            isSearching = true
            let response = try await APIClient.searchChats(
                query: query,
                inbox: inbox.rawValue,
                accountIDs: filter.accountIDs
            )
            guard !Task.isCancelled,
                  latestSearchRequestID == requestID,
                  selectedFilter.id == filter.id,
                  self.session == session,
                  searchQuery.trimmed == query else { return }
            searchResults = response.items
        } catch {
            guard !Task.isCancelled, latestSearchRequestID == requestID else { return }
            searchResults = []
        }
    }

    func resetSearch() {
        latestSearchRequestID = nil
        searchResults = nil
        isSearching = false
    }

    // MARK: - Chat actions

    func setChatPinned(_ chatID: String, pinned: Bool) async {
        guard pinningChatIDs.insert(chatID).inserted else { return }
        let session = session
        defer {
            if self.session == session { pinningChatIDs.remove(chatID) }
        }
        do {
            try await APIClient.pinChat(chatID: chatID, pinned: pinned)
            guard self.session == session else { return }
            // Read the cached summary, including the server's saved pin order.
            let updated = try await APIClient.getChat(chatID: chatID)
            guard self.session == session else { return }
            applyChatUpsert(updated)
        } catch {
            guard self.session == session else { return }
            pinError = error.localizedDescription
        }
    }

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
        guard mutingChatIDs.insert(chatID).inserted else { return }
        let session = session
        defer { if self.session == session { mutingChatIDs.remove(chatID) } }
        muteError = nil
        let previous = chat(byID: chatID)
        updateChat(chatID) { $0.isMuted = muted }

        do {
            let updated = try await APIClient.muteChat(chatID: chatID, muted: muted)
            guard self.session == session else { return }
            applyChatUpsert(updated)
        } catch {
            guard self.session == session else { return }
            let message = error.localizedDescription
            // One of the two server writes may have succeeded. Show the actual
            // state instead of restoring a snapshot that can hide a saved mute.
            let actual = try? await APIClient.getChat(chatID: chatID)
            guard self.session == session else { return }
            if let actual {
                applyChatUpsert(actual)
            } else if let previous {
                updateChat(chatID) { $0.isMuted = previous.isMuted }
            }
            try? await notificationService.syncNotificationPreferences()
            guard self.session == session else { return }
            muteError = message
            return
        }
        do { try await notificationService.syncNotificationPreferences() }
        catch {
            guard self.session == session else { return }
            muteError = "Mute setting saved, but notification delivery could not be updated. Reopen Relay to retry."
        }
    }

    func markChatAsRead(_ chatID: String) async {
        let session = session
        notificationService.clearDeliveredNotifications(for: chatID)
        let previous = chat(byID: chatID)
        updateChat(chatID) {
            $0.unreadCount = 0
            $0.isMarkedUnread = false
        }

        do {
            try await APIClient.markChatAsRead(chatID: chatID)
        } catch {
            guard self.session == session else { return }
            if let previous { updateChat(chatID) { $0 = previous } }
            chatsError = error.localizedDescription
        }
    }

    func markChatAsUnread(_ chatID: String) async {
        let session = session
        do {
            let updated = try await APIClient.markChatAsUnread(chatID: chatID)
            guard self.session == session else { return }
            applyChatUpsert(updated)
        } catch {
            guard self.session == session else { return }
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

        pinnedChats.removeAll { $0.id == incoming.id }
        if incoming.isPinned == true { pinnedChats.append(incoming) }

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
        pinnedChats.removeAll { $0.id == chatID }
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
        if let index = pinnedChats.firstIndex(where: { $0.id == chatID }) {
            mutate(&pinnedChats[index])
        }
        if var results = searchResults,
           let searchIndex = results.firstIndex(where: { $0.id == chatID }) {
            mutate(&results[searchIndex])
            searchResults = results
        }
    }

    /// Empties the sidebar, which also clears the selection and open timeline.
    func resetChatList() {
        pinnedChats = []
        pinningChatIDs = []
        pinError = nil
        setChats([])
        selectedChatID = nil
        hasMoreChats = false
        lastLoadedFilterID = nil
        chatWindowSize = Self.chatPageSize
        chatsError = nil
    }
}
