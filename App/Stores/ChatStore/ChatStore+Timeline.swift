import Foundation

/// The open chat's timeline. Only the open chat keeps messages in memory;
/// background chats read theirs from the database when opened.
extension ChatStore {
    /// The open timeline without server echoes that an outgoing row still shows.
    var timelineMessages: [Message] {
        let shownByOutgoingRows = Set(outgoingMessages.flatMap(\.confirmedMessageIDs))
        guard !shownByOutgoingRows.isEmpty else { return messages }
        return messages.filter { !shownByOutgoingRows.contains($0.id) }
    }

    /// Reloads the open chat's newest page on open, reconnect, or resync.
    /// Steady-state changes arrive as events.
    func loadMessages() async {
        guard let chatID = selectedChatID else { return }

        let generation = timelineGeneration
        isLoadingMessages = true
        defer { if generation == timelineGeneration { isLoadingMessages = false } }

        do {
            let response = try await APIClient.listMessages(chatID: chatID)
            guard generation == timelineGeneration else { return }

            messagesError = nil
            if let readKey = response.lastReadByOtherSortKey { lastReadByOtherSortKey = readKey }
            reconcileOutgoingMessages(with: response.items, chatID: chatID)
            upsertMessages(response.items)
            hasLoadedTimeline = true
            if olderMessagesCursor == nil {
                olderMessagesCursor = response.oldestCursor
                hasMoreOlderMessages = response.hasMore
            }
        } catch {
            guard generation == timelineGeneration else { return }
            handleMessageError(error)
        }
    }

    func loadOlderMessages() async {
        guard let chatID = selectedChatID, hasLoadedTimeline, hasMoreOlderMessages,
              !isLoadingOlderMessages, var cursor = olderMessagesCursor else { return }

        let generation = timelineGeneration
        isLoadingOlderMessages = true
        defer { if generation == timelineGeneration { isLoadingOlderMessages = false } }

        do {
            repeat {
                let response = try await APIClient.listMessages(chatID: chatID, cursor: cursor)
                guard generation == timelineGeneration else { return }

                let countBefore = messages.count
                upsertMessages(response.items)
                hasMoreOlderMessages = response.hasMore && response.oldestCursor != cursor
                olderMessagesCursor = response.oldestCursor
                // A local page can contain only hidden events. Continue until a
                // visible row or the database boundary, without a retry button.
                guard messages.count == countBefore, hasMoreOlderMessages,
                      let next = response.oldestCursor else { return }
                cursor = next
            } while true
        } catch {
            guard generation == timelineGeneration else { return }
            handleMessageError(error)
        }
    }

    /// Inserts or replaces messages by ID. Every copy the core sends is
    /// complete, so the newest one wins outright.
    func upsertMessages(_ incoming: [Message]) {
        handoffTyping(to: incoming)
        var byID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for message in incoming {
            byID[message.id] = message
            if !message.hasUnresolvedReel { failedMediaIDs.remove(message.id) }
        }
        let updated = byID.values.sorted { ($0.numericSortKey, $0.id) < ($1.numericSortKey, $1.id) }
        // Database reloads often equal the event-applied state; skip the no-op write.
        if updated != messages { messages = updated }
    }

    /// Clears the timeline and composer state for a newly opened chat.
    func resetTimeline() {
        clearTyping()
        typingMessageRowIDs = [:]
        failedMediaIDs = []
        timelineGeneration = UUID()
        loadMessagesTask?.cancel()
        loadMessagesTask = nil
        messages = []
        hasLoadedTimeline = false
        olderMessagesCursor = nil
        hasMoreOlderMessages = false
        isLoadingOlderMessages = false
        isLoadingMessages = false
        lastReadByOtherSortKey = nil
        replyingToMessage = nil
        editingMessage = nil
        messagesError = nil
    }

    // MARK: - Reel media

    /// How many reels may resolve at once.
    static let maxConcurrentMediaResolves = 2

    /// Asks the bridge to replace a reel link with its video, up to
    /// `maxConcurrentMediaResolves` at once. Attempts live here rather than in
    /// the row so scrolling and view recreation cannot duplicate a request or retry loop.
    func resolveMedia(_ message: Message, retry: Bool = false) async {
        guard isSignedIn, message.hasUnresolvedReel,
              selectedChatID == message.chatID, !Task.isCancelled,
              resolvingMediaIDs.count < Self.maxConcurrentMediaResolves,
              !resolvingMediaIDs.contains(message.id),
              retry || !failedMediaIDs.contains(message.id) else { return }
        let session = session
        resolvingMediaIDs.insert(message.id)
        failedMediaIDs.remove(message.id)
        defer {
            if self.session == session { resolvingMediaIDs.remove(message.id) }
        }
        do {
            try await APIClient.resolveMedia(chatID: message.chatID, messageID: message.id)
            // The response acknowledges the bridge edit, not its arrival in
            // local sync. Keep the spinner until the original bubble updates,
            // checking local state only for up to ten seconds.
            for _ in 0..<40 {
                guard self.session == session, selectedChatID == message.chatID else { return }
                guard messages.contains(where: { $0.id == message.id && $0.hasUnresolvedReel }) else { return }
                try await Task.sleep(for: .milliseconds(250))
            }
            failedMediaIDs.insert(message.id)
        } catch is CancellationError {
            // Sync replaced the row, or it left the viewport. Do not turn a
            // successful resolution into an error on the replacement row.
        } catch {
            guard self.session == session else { return }
            failedMediaIDs.insert(message.id)
        }
    }
}

private extension Message {
    /// Whether the message still shows a reel link rather than its video.
    var hasUnresolvedReel: Bool {
        attachments?.contains { $0.type == .reel } == true
    }
}
