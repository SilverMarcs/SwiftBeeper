import Foundation

/// The Messages section of the chat list's search: messages in any chat
/// matching the query, below the matching chats.
extension ChatStore {
    /// Replaces the results with a new search's first page; nil clears them.
    func setMessageSearchResults(_ output: SearchMessagesOutput?) {
        messageSearchResults = output?.items ?? []
        messageSearchChats = Dictionary(output?.chats.map { ($0.id, $0) } ?? [], uniquingKeysWith: { first, _ in first })
        messageSearchCursor = output?.cursor
        hasMoreMessageSearchResults = output?.hasMore == true
        isLoadingMoreMessageSearchResults = false
    }

    /// Appends the next page of results for the current query.
    func loadMoreMessageSearchResults() async {
        guard isSearchActive, hasMoreMessageSearchResults, !isLoadingMoreMessageSearchResults,
              let cursor = messageSearchCursor else { return }
        let query = searchQuery.trimmed
        let filter = selectedFilter
        let session = session
        isLoadingMoreMessageSearchResults = true
        defer { isLoadingMoreMessageSearchResults = false }

        guard let output = try? await APIClient.searchMessages(query: query, accountIDs: filter.accountIDs, cursor: cursor),
              self.session == session, searchQuery.trimmed == query, selectedFilter.id == filter.id,
              messageSearchCursor == cursor else { return }
        let known = Set(messageSearchResults?.map(\.id) ?? [])
        messageSearchResults = (messageSearchResults ?? []) + output.items.filter { !known.contains($0.id) }
        for chat in output.chats where messageSearchChats[chat.id] == nil {
            messageSearchChats[chat.id] = chat
        }
        messageSearchCursor = output.cursor ?? cursor
        hasMoreMessageSearchResults = output.hasMore
    }

    /// Opens a result's chat at the message, or its thread for a reply kept
    /// to one. The search stays, for going back to the results. The result's
    /// chat is a light copy, so the full chat is used where known.
    func openMessageSearchResult(_ message: Message) async {
        var chat = chat(byID: message.chatID)
        if chat == nil {
            chat = try? await APIClient.getChat(chatID: message.chatID)
        }
        guard let chat = chat ?? messageSearchChats[message.chatID] else { return }
        if selectedChatID != chat.id {
            openChat(chat, keepingSearch: true)
            // The newest page loads first; the message may already be in it.
            await loadMessagesTask?.value
        } else {
            // Shows the open chat again on iPhone, where the list covers it.
            chatNavigationID = UUID()
        }
        await revealMessage(message)
    }
}
