import Foundation

/// Jumping to a message outside the loaded timeline, such as a search result.
/// The timeline then holds a stretch of the conversation around it instead of
/// everything newer: newer pages load as the reader scrolls down, and sending
/// or Jump to Latest returns to the newest page.
extension ChatStore {
    /// Shows a message of the open chat: a thread reply in its thread, and
    /// anything else in the timeline, loading the page around it when it
    /// isn't loaded.
    func revealMessage(_ message: Message) async {
        guard message.chatID == selectedChatID else { return }
        if message.isHiddenThreadReply, let rootID = message.threadRootID {
            showThread(rootID: rootID, chatID: message.chatID)
            return
        }
        if !messages.contains(where: { $0.id == message.id }) {
            guard await loadMessageWindow(around: message.id) else { return }
        }
        messageRevealRequest = MessageRevealRequest(messageID: message.id)
    }

    /// Loads the next newer page of a stretch that stops short of the newest.
    func loadNewerMessages() async {
        guard let chatID = selectedChatID, hasLoadedTimeline, hasMoreNewerMessages,
              !isLoadingNewerMessages, var cursor = newerMessagesCursor else { return }

        let generation = timelineGeneration
        isLoadingNewerMessages = true
        defer { if generation == timelineGeneration { isLoadingNewerMessages = false } }

        do {
            repeat {
                let response = try await APIClient.listMessages(chatID: chatID, after: cursor)
                guard generation == timelineGeneration else { return }

                await loadQuotedMessages(for: response.items)
                guard generation == timelineGeneration else { return }
                let countBefore = messages.count
                upsertMessages(response.items)
                hasMoreNewerMessages = response.hasMoreNewer == true && response.newestCursor != cursor
                newerMessagesCursor = response.newestCursor
                if !hasMoreNewerMessages {
                    // Messages that arrived while this stretch was short of the
                    // newest were held back; pick them up now it reaches it.
                    await loadMessages()
                    return
                }
                // A page can hold only hidden events; continue to a visible row.
                guard messages.count == countBefore, let next = response.newestCursor else { return }
                cursor = next
            } while true
        } catch {
            guard generation == timelineGeneration else { return }
            handleMessageError(error)
        }
    }

    /// Leaves a stretch that stops short of the newest for the newest page.
    func showLatestMessages() {
        guard hasMoreNewerMessages else { return }
        timelineGeneration = UUID()
        timelineWindowID = UUID()
        loadMessagesTask?.cancel()
        messages = []
        hasLoadedTimeline = false
        olderMessagesCursor = nil
        hasMoreOlderMessages = false
        isLoadingOlderMessages = false
        hasMoreNewerMessages = false
        isLoadingNewerMessages = false
        newerMessagesCursor = nil
        messageRevealRequest = nil
        loadMessagesTask = Task { [weak self] in
            await self?.loadMessages()
        }
    }

    /// Drops incoming messages beyond a stretch that stops short of the
    /// newest, which reads them from the database as it pages down. Updates
    /// to loaded messages still apply.
    func messagesInLoadedWindow(_ incoming: [Message]) -> [Message] {
        guard hasMoreNewerMessages, let newest = messages.last else { return incoming }
        return incoming.filter { message in
            message.numericSortKey <= newest.numericSortKey || messages.contains { $0.id == message.id }
        }
    }

    /// Replaces the loaded messages with the page around a message. Returns
    /// whether the message is now loaded.
    private func loadMessageWindow(around messageID: Message.ID) async -> Bool {
        guard let chatID = selectedChatID else { return false }
        let generation = UUID()
        timelineGeneration = generation
        loadMessagesTask?.cancel()
        isLoadingOlderMessages = false
        isLoadingNewerMessages = false

        do {
            let response = try await APIClient.listMessages(chatID: chatID, around: messageID)
            guard generation == timelineGeneration else { return false }
            await loadQuotedMessages(for: response.items)
            guard generation == timelineGeneration else { return false }

            timelineWindowID = UUID()
            messages = []
            upsertMessages(response.items)
            olderMessagesCursor = response.oldestCursor
            hasMoreOlderMessages = response.hasMore
            newerMessagesCursor = response.newestCursor
            hasMoreNewerMessages = response.hasMoreNewer == true
            hasMoreServerHistory = response.hasServerHistory
            hasLoadedTimeline = true
            return messages.contains { $0.id == messageID }
        } catch {
            guard generation == timelineGeneration else { return false }
            handleMessageError(error)
            return false
        }
    }
}
