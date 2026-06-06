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

/// The app's single source of truth: chat list, the open chat's timeline, the
/// composer, and realtime event handling. The timeline is *event-sourced* — the
/// backend hydrates each `message.upserted` event with the full message, so we
/// apply it directly instead of refetching. Only the open chat keeps messages in
/// memory; the sidebar is kept current by a light, debounced chat-list refresh.
@MainActor
@Observable
final class ChatStore: RealtimeEventHandler {
    private let realtimeService: RealtimeService
    private let notificationService: NotificationService

    // MARK: Chat list

    private(set) var chats: [Chat] = []
    private(set) var hasMoreChats = false
    private(set) var isLoadingMoreChats = false
    private(set) var isLoadingChats = false
    private(set) var chatsError: String?
    private(set) var chatsErrorIsAuth: Bool = false
    private(set) var isRecoveringAuth: Bool = false
    var selectedInboxFilter: InboxFilter = .primary
    var searchQuery: String = ""
    var searchResults: [Chat]?
    var isSearching = false
    private var lowPriorityChatIDs: Set<String> = []
    private var chatsCursor: String?
    private var lastLoadedInboxFilter: InboxFilter?
    private var chatsByID: [String: Chat] = [:]

    var selectedChatID: String? {
        didSet {
            guard oldValue != selectedChatID else { return }
            print("🟢 [store] selectedChatID \(oldValue ?? "nil") -> \(selectedChatID ?? "nil")")
            // Only the open chat keeps a timeline in memory — reset it on switch.
            messages = []
            messagesChatID = nil
            hasMoreOlderMessages = false
            lastReadByOtherSortKey = nil
            replyingToMessage = nil
            editingMessage = nil
            messagesError = nil

            // Own the open-chat load here, not in the detail view's `.task`. A
            // debounced chat-list refresh can briefly drop the open chat from
            // `chats`, which collapses the detail view and cancels a view-owned
            // load — and that cancellation also kills the in-flight request,
            // leaving an empty timeline that never recovers (same view id, so the
            // `.task` doesn't re-fire). A store-owned task survives that churn; we
            // cancel it only when the selection actually changes.
            loadMessagesTask?.cancel()
            if let chatID = selectedChatID {
                print("🟢 [store] launching loadMessagesTask for \(chatID)")
                loadMessagesTask = Task { [weak self] in await self?.loadMessages(for: chatID) }
            } else {
                loadMessagesTask = nil
            }
        }
    }

    // MARK: Open-chat timeline

    private(set) var messages: [Message] = []
    /// Which chat `messages` currently belongs to (guards against load races).
    private(set) var messagesChatID: String?
    private(set) var hasMoreOlderMessages = false
    /// Furthest sortKey another participant has read in the open chat.
    var lastReadByOtherSortKey: String?
    private var latestLoadRequestID: UUID?
    private(set) var isLoadingOlderMessages = false
    private(set) var isLoadingMessages = false
    private(set) var isSendingMessage = false
    var messagesError: String?
    private(set) var uploadProgress: Double?

    // MARK: Composer

    var replyingToMessage: Message?
    var editingMessage: Message?
    var pendingAttachments: [PendingAttachment] = []

    var activeComposerMessage: Message? {
        editingMessage ?? replyingToMessage
    }

    // MARK: Realtime / notifications

    private var scheduledChatsRefreshTask: Task<Void, Never>?
    private var scheduledMessagesRefreshTask: Task<Void, Never>?
    private var loadMessagesTask: Task<Void, Never>?
    private var lastNotifiedMessageIDByChatID: [String: String] = [:]

    init(realtimeService: RealtimeService, notificationService: NotificationService) {
        self.realtimeService = realtimeService
        self.notificationService = notificationService
        realtimeService.eventHandler = self
    }

    /// Convenience for previews and tests.
    convenience init() {
        self.init(realtimeService: RealtimeService(), notificationService: NotificationService())
    }

    // MARK: - Derived chat-list accessors

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

    /// Which chat to fall back to when the current selection becomes invalid.
    /// macOS and iPad auto-select the first chat; iPhone stays manual (nil).
    private var autoSelectedChatID: String? {
        Device.isIPhone ? nil : chats.first?.id
    }

    func chat(byID chatID: String) -> Chat? {
        chatsByID[chatID] ?? searchResults?.first(where: { $0.id == chatID })
    }

    func isPrimaryInboxChat(_ chat: Chat) -> Bool {
        !lowPriorityChatIDs.contains(chat.id) && chat.isArchived != true
    }

    // MARK: - Open-chat accessors

    func messages(for chatID: String) -> [Message] {
        guard chatID == messagesChatID else { return [] }
        return messages.filter(\.isDisplayable)
    }

    func message(byID messageID: String, in chatID: String) -> Message? {
        guard chatID == messagesChatID else { return nil }
        return messages.first(where: { $0.id == messageID })
    }

    func hasMoreMessages(for chatID: String) -> Bool {
        chatID == messagesChatID && hasMoreOlderMessages
    }

    /// True if the given outgoing message has been read by the other side.
    func isReadByOther(message: Message) -> Bool {
        guard message.chatID == messagesChatID,
              let readKey = lastReadByOtherSortKey, !readKey.isEmpty else {
            return false
        }
        guard let msgSort = Int64(message.sortKey), let readSort = Int64(readKey) else {
            return message.sortKey <= readKey
        }
        return msgSort <= readSort
    }

    // MARK: - Lifecycle

    func updateAccessToken(_ accessToken: String) async {
        if accessToken == APIClient.accessToken { return }

        APIClient.accessToken = accessToken

        if accessToken.isEmpty {
            realtimeService.stop()
            selectedChatID = nil
            clearState()
            return
        }

        await loadChats()
        realtimeService.start()
    }

    /// Called once the embedded backend is confirmed running after the app
    /// returns to the foreground. The websocket and any in-flight requests die
    /// while the app is suspended, so reconnect realtime (its `ready` event
    /// re-syncs the chat list) and reload the open chat's timeline.
    func handleAppForeground() {
        guard !APIClient.accessToken.isEmpty else { return }
        realtimeService.start()
        if let chatID = selectedChatID {
            loadMessagesTask?.cancel()
            loadMessagesTask = Task { [weak self] in await self?.loadMessages(for: chatID) }
        }
    }

    func clearState() {
        restoreListState(.empty)
        lowPriorityChatIDs = []
        searchResults = nil
        searchQuery = ""
        isSearching = false
        loadMessagesTask?.cancel()
        loadMessagesTask = nil
        messages = []
        messagesChatID = nil
        hasMoreOlderMessages = false
        lastReadByOtherSortKey = nil
        latestLoadRequestID = nil
        messagesError = nil
        replyingToMessage = nil
        editingMessage = nil
        pendingAttachments = []
        uploadProgress = nil
        lastNotifiedMessageIDByChatID = [:]
    }

    // MARK: - Chat list loading

    func ensureLowPriorityIDsLoaded() async {
        guard lowPriorityChatIDs.isEmpty else { return }
        lowPriorityChatIDs = (try? await APIClient.listLowPriorityChatIDs()) ?? []
    }

    func loadChats() async {
        await performLoadChats(retriesRemaining: 1)
    }

    private func performLoadChats(retriesRemaining: Int) async {
        guard !APIClient.accessToken.isEmpty else {
            restoreListState(.empty)
            return
        }

        let snapshot = captureListState()
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

            print("🟣 [store] performLoadChats COMMIT count=\(refreshedChats.count) selectedChatID=\(selectedChatID ?? "nil") inChatsByID=\(chatsByID[selectedChatID ?? ""] != nil)")
            // macOS/iPad auto-select the first chat (and on launch / filter
            // change); iPhone navigation is manual, so leave it unselected.
            if selectedChatID == snapshot.selectedChatID {
                if let existingSelectedChatID = snapshot.selectedChatID, chatsByID[existingSelectedChatID] != nil {
                    selectedChatID = existingSelectedChatID
                } else if chatsByID[selectedChatID ?? ""] == nil {
                    print("🟣 [store] performLoadChats DESELECT (open chat absent from refreshed list) was=\(selectedChatID ?? "nil")")
                    selectedChatID = autoSelectedChatID
                }
            } else if chatsByID[selectedChatID ?? ""] == nil {
                print("🟣 [store] performLoadChats DESELECT-2 was=\(selectedChatID ?? "nil")")
                selectedChatID = autoSelectedChatID
            }
        } catch {
            if retriesRemaining > 0,
               case APIError.http(401, _) = error,
               APIClient.accessToken != tokenAtStart {
                await performLoadChats(retriesRemaining: retriesRemaining - 1)
                return
            }
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
            restoreListState(snapshot)
            chatsError = error.localizedDescription
            chatsErrorIsAuth = { if case APIError.http(401, _) = error { return true } else { return false } }()
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
            // Silently fail on pagination errors; the user can scroll again to retry.
        }
    }

    // MARK: - Search

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
            updateChat(chatID) { $0 = $0.merging(detail: detail) }
            if chatsByID[chatID] == nil, var results = searchResults,
               let index = results.firstIndex(where: { $0.id == chatID }) {
                results[index] = results[index].merging(detail: detail)
                searchResults = results
            }
        } catch {
            // Non-critical; we still have list data.
        }
    }

    // MARK: - Chat actions

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

    func archiveChat(_ chatID: String) async { await setArchived(chatID, archived: true) }
    func unarchiveChat(_ chatID: String) async { await setArchived(chatID, archived: false) }

    private func setArchived(_ chatID: String, archived: Bool) async {
        guard !APIClient.accessToken.isEmpty else { return }
        do {
            try await APIClient.archiveChat(chatID: chatID, archived: archived)
            setChats(chats.filter { $0.id != chatID })
            if selectedChatID == chatID {
                selectedChatID = autoSelectedChatID
            }
        } catch {
            chatsError = error.localizedDescription
        }
    }

    func muteChat(_ chatID: String) async { await setChatMuted(chatID, muted: true) }
    func unmuteChat(_ chatID: String) async { await setChatMuted(chatID, muted: false) }

    private func setChatMuted(_ chatID: String, muted: Bool) async {
        guard !APIClient.accessToken.isEmpty else { return }

        let previous = chatsByID[chatID]
        updateChat(chatID) { $0.isMuted = muted }

        do {
            try await APIClient.muteChat(chatID: chatID, muted: muted)
        } catch {
            if let previous { updateChat(chatID) { $0 = previous } }
            chatsError = error.localizedDescription
        }
    }

    func markChatAsRead(_ chatID: String) async {
        guard !APIClient.accessToken.isEmpty else { return }

        let previous = chatsByID[chatID]
        updateChat(chatID) { $0.unreadCount = 0 }

        do {
            try await APIClient.markChatAsRead(chatID: chatID)
        } catch {
            if let previous { updateChat(chatID) { $0 = previous } }
            chatsError = error.localizedDescription
        }
    }

    // MARK: - Message loading (open chat only)

    /// Full-refreshes the open chat's timeline. Used on first appearance, after a
    /// send/delete, and on reconnect; steady-state updates arrive via realtime.
    func loadMessages(for chatID: String) async {
        guard !APIClient.accessToken.isEmpty, chatID == selectedChatID else {
            print("🟠 [store] loadMessages EARLY-RETURN chat=\(chatID) selectedChatID=\(selectedChatID ?? "nil") tokenEmpty=\(APIClient.accessToken.isEmpty)")
            return
        }
        print("🟠 [store] loadMessages START chat=\(chatID)")

        let requestID = UUID()
        latestLoadRequestID = requestID
        isLoadingMessages = true
        defer {
            if latestLoadRequestID == requestID { isLoadingMessages = false }
        }

        do {
            let response = try await APIClient.listMessages(chatID: chatID)
            guard latestLoadRequestID == requestID, chatID == selectedChatID else {
                print("🟠 [store] loadMessages POST-AWAIT DROP chat=\(chatID) selectedChatID=\(selectedChatID ?? "nil") staleRequest=\(latestLoadRequestID != requestID) gotItems=\(response.items.count)")
                return
            }
            print("🟠 [store] loadMessages COMMIT chat=\(chatID) items=\(response.items.count)")

            // 2026-06-05: every write below only fires on real change. Observation
            // invalidates observers on ANY write (it doesn't compare values), and a
            // send triggers several overlapping refetches (WS reconcile + post-send
            // refresh) — unconditional writes re-rendered the whole timeline mid
            // scroll animation, visibly shifting the scroll position.
            if messagesError != nil { messagesError = nil }
            if let readKey = response.lastReadByOtherSortKey, readKey != lastReadByOtherSortKey {
                lastReadByOtherSortKey = readKey
            }
            let existing = messagesChatID == chatID ? messages : []
            let merged = refreshedMessages(existing: existing, latestPage: response.items)
            if merged != messages { messages = merged }
            if messagesChatID != chatID { messagesChatID = chatID }
            if hasMoreOlderMessages != response.hasMore { hasMoreOlderMessages = response.hasMore }
        } catch {
            print("🟠 [store] loadMessages CATCH chat=\(chatID) cancelLike=\(isCancellationLikeError(error)) stale=\(latestLoadRequestID != requestID) error=\(error)")
            guard latestLoadRequestID == requestID else { return }
            handleMessageError(error)
        }
    }

    /// Awaitable handle for the store-owned open-chat load, so the detail view can
    /// sequence its scroll/unread UI without owning the request's lifetime.
    func awaitCurrentMessagesLoad() async {
        print("🔵 [store] awaitCurrentMessagesLoad begin hasTask=\(loadMessagesTask != nil)")
        await loadMessagesTask?.value
        print("🔵 [store] awaitCurrentMessagesLoad end")
    }

    @discardableResult
    func loadOlderMessages(for chatID: String) async -> Bool {
        guard !APIClient.accessToken.isEmpty else { return false }
        guard chatID == messagesChatID, hasMoreOlderMessages, !isLoadingOlderMessages else { return false }
        guard let oldestMessage = messages.first else { return false }

        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }

        do {
            let response = try await APIClient.listMessages(
                chatID: chatID,
                cursor: oldestMessage.sortKey,
                direction: "before"
            )
            guard chatID == messagesChatID else { return false }

            let merged = mergedMessages(existing: messages, incoming: normalizedMessages(response.items))
            let changed = merged != messages
            if changed { messages = merged }
            hasMoreOlderMessages = response.hasMore
            return changed
        } catch {
            handleMessageError(error)
            return false
        }
    }

    /// Applies messages delivered by a realtime event to the open chat's timeline.
    private func applyIncomingMessages(_ incoming: [Message], chatID: String) {
        guard chatID == selectedChatID, chatID == messagesChatID, !incoming.isEmpty else { return }
        let merged = mergedMessages(existing: messages, incoming: normalizedMessages(incoming))
        if merged != messages { messages = merged }
    }

    // MARK: - Sending / editing

    func clearPendingAttachments() {
        pendingAttachments = []
        uploadProgress = nil
    }

    func removePendingAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    /// Reloads the open chat (and the sidebar) after the local user mutates it.
    func refreshAfterMessageMutation(chatID: String) async {
        async let chatsRefresh: Void = loadChats()
        async let messagesRefresh: Void = loadMessages(for: chatID)
        _ = await (chatsRefresh, messagesRefresh)
    }

    func sendMessage(text: String, attachments: [PendingAttachment], to chatID: String) async -> Bool {
        guard !APIClient.accessToken.isEmpty else { return false }

        let trimmedText = text.trimmed
        let hasText = !trimmedText.isEmpty
        guard hasText || !attachments.isEmpty else { return false }

        isSendingMessage = true
        defer {
            isSendingMessage = false
            uploadProgress = nil
        }

        let replyToID = replyingToMessage?.id

        do {
            let firstAttachmentInput = try await uploadAttachment(attachments.first, chatID: chatID)
            _ = try await APIClient.sendMessage(
                chatID: chatID,
                text: hasText ? trimmedText : nil,
                replyToMessageID: replyToID,
                attachment: firstAttachmentInput
            )

            for attachment in attachments.dropFirst() {
                let attachmentInput = try await uploadAttachment(attachment, chatID: chatID)
                _ = try await APIClient.sendMessage(chatID: chatID, text: nil, attachment: attachmentInput)
            }

            replyingToMessage = nil
            messagesError = nil
            return true
        } catch {
            handleMessageError(error)
            return false
        }
    }

    private func uploadAttachment(_ attachment: PendingAttachment?, chatID: String) async throws -> MessageAttachmentInput? {
        guard let attachment else { return nil }

        uploadProgress = 0
        let uploadResult = try await APIClient.uploadAsset(
            fileData: attachment.fileData,
            fileName: attachment.fileName,
            mimeType: attachment.mimeType,
            onProgress: { [weak self] progress in
                self?.uploadProgress = progress
            }
        )

        if let error = uploadResult.error, !error.isEmpty {
            handleMessageError(message: "Upload failed: \(error)")
            throw UploadError.serverError(error)
        }

        var size: AttachmentSizeInput?
        if let w = uploadResult.width, let h = uploadResult.height {
            size = AttachmentSizeInput(width: w, height: h)
        }

        return MessageAttachmentInput(
            uploadID: uploadResult.uploadID,
            mimeType: attachment.mimeType,
            fileName: attachment.fileName,
            size: size,
            duration: uploadResult.duration,
            type: nil
        )
    }

    private enum UploadError: Error {
        case serverError(String)
    }

    func setReplyTo(_ message: Message?) {
        if message != nil { editingMessage = nil }
        replyingToMessage = message
    }

    func canEdit(_ message: Message, in chat: Chat) -> Bool {
        guard message.isOutgoing(in: chat) else { return false }
        if chat.allowsUnlimitedMessageEdits { return true }
        return Date().timeIntervalSince(message.timestamp) <= 15 * 60
    }

    func startEditing(_ message: Message, in chat: Chat) {
        guard canEdit(message, in: chat) else { return }
        replyingToMessage = nil
        editingMessage = message
    }

    func cancelEditing() {
        editingMessage = nil
    }

    func cancelComposerAction() {
        replyingToMessage = nil
        editingMessage = nil
    }

    func saveEdit(newText: String) async -> Bool {
        guard let message = editingMessage else { return false }
        guard !APIClient.accessToken.isEmpty else { return false }

        let trimmedText = newText.trimmed
        guard !trimmedText.isEmpty else { return false }

        isSendingMessage = true
        defer { isSendingMessage = false }

        do {
            _ = try await APIClient.editMessage(chatID: message.chatID, messageID: message.id, text: trimmedText)
            editingMessage = nil
            messagesError = nil
            return true
        } catch {
            handleMessageError(error)
            return false
        }
    }

    func addReaction(to messageID: String, in chatID: String, reactionKey: String) async {
        guard !APIClient.accessToken.isEmpty else { return }
        do {
            _ = try await APIClient.addReaction(chatID: chatID, messageID: messageID, reactionKey: reactionKey)
        } catch {
            handleMessageError(error)
        }
    }

    func removeReaction(from messageID: String, in chatID: String, reactionKey: String) async {
        guard !APIClient.accessToken.isEmpty else { return }
        do {
            _ = try await APIClient.removeReaction(chatID: chatID, messageID: messageID, reactionKey: reactionKey)
        } catch {
            handleMessageError(error)
        }
    }

    func deleteMessage(_ messageID: String, in chatID: String) async {
        guard !APIClient.accessToken.isEmpty else { return }
        do {
            _ = try await APIClient.deleteMessage(chatID: chatID, messageID: messageID)
        } catch {
            handleMessageError(error)
        }
    }

    // MARK: - RealtimeEventHandler

    nonisolated func realtimeDidConnect() {
        Task { @MainActor in
            scheduleChatsRefresh()
            if let chatID = selectedChatID {
                scheduleMessagesRefresh(chatID: chatID)
            }
        }
    }

    nonisolated func realtimeDidUpsertChat(chatID: String?) {
        Task { @MainActor in scheduleChatsRefresh() }
    }

    nonisolated func realtimeDidDeleteChat(chatID: String?) {
        Task { @MainActor in
            if let chatID {
                removeChatLocally(chatID)
            } else {
                scheduleChatsRefresh()
            }
        }
    }

    nonisolated func realtimeDidUpsertMessages(chatID: String?, messages incoming: [Message]) {
        Task { @MainActor in
            guard let chatID else { scheduleChatsRefresh(); return }

            if chatID == selectedChatID {
                // Apply the payload for instant new-message rendering, then reconcile
                // (debounced) so reactions/edits/deletes — which arrive as separate
                // events — settle correctly. Both touch only the open chat.
                applyIncomingMessages(incoming, chatID: chatID)
                scheduleMessagesRefresh(chatID: chatID)
            }

            // Sidebar metadata (preview, unread, ordering) stays server-authoritative.
            scheduleChatsRefresh()

            if chatID != selectedChatID {
                await notify(incoming, chatID: chatID)
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

    nonisolated func realtimeDidUpdateReceipt(chatID: String?, entries: [[String: String]]?) {
        Task { @MainActor in
            guard let chatID, chatID == selectedChatID,
                  let readKey = entries?.first?["lastReadByOtherSortKey"] else { return }
            lastReadByOtherSortKey = readKey
        }
    }

    nonisolated func realtimeDidReceiveError(_ message: String) {
        Task { @MainActor in messagesError = message }
    }

    // MARK: - Realtime helpers

    private func scheduleChatsRefresh() {
        scheduledChatsRefreshTask?.cancel()
        scheduledChatsRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            print("🟣 [store] scheduledChatsRefresh -> loadChats")
            await self.loadChats()
        }
    }

    private func scheduleMessagesRefresh(chatID: String) {
        scheduledMessagesRefreshTask?.cancel()
        scheduledMessagesRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            await self.loadMessages(for: chatID)
        }
    }

    /// Posts notifications for a background chat directly from the realtime payload.
    private func notify(_ incoming: [Message], chatID: String) async {
        await ensureLowPriorityIDsLoaded()
        guard let chat = chat(byID: chatID), chat.isMuted != true, isPrimaryInboxChat(chat) else { return }

        for message in incoming {
            if message.isOutgoing(in: chat) || message.isMembershipEvent || message.isReaction { continue }
            if Date().timeIntervalSince(message.timestamp) > 60 { continue }
            if message.id == lastNotifiedMessageIDByChatID[chatID] { continue }
            lastNotifiedMessageIDByChatID[chatID] = message.id
            notificationService.postNewMessageNotification(message: message, chatTitle: chat.displayTitle)
        }
    }

    // MARK: - Private storage helpers

    private func setChats(_ newChats: [Chat]) {
        // 2026-06-05: skip identical commits. The sidebar refresh fires several
        // times around a send; rewriting `chats`/`chatsByID` with equal values
        // still invalidates every observer (Observation doesn't compare), which
        // re-rendered the open chat's whole timeline via `selectedChat`.
        guard newChats != chats else { return }
        chats = newChats
        chatsByID = Dictionary(newChats.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    private func updateChat(_ chatID: String, _ mutate: (inout Chat) -> Void) {
        if let index = chats.firstIndex(where: { $0.id == chatID }) {
            mutate(&chats[index])
            chatsByID[chatID] = chats[index]
        }
        if var results = searchResults,
           let searchIndex = results.firstIndex(where: { $0.id == chatID }) {
            mutate(&results[searchIndex])
            searchResults = results
        }
    }

    private func mergedChatsPreservingExistingContext(
        refreshedChats: [Chat],
        existingChats: [Chat],
        shouldPreserveExistingChats: Bool
    ) -> [Chat] {
        let existingByID = Dictionary(existingChats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let mergedRefreshed = refreshedChats.map { refreshed in
            existingByID[refreshed.id]?.merging(detail: refreshed) ?? refreshed
        }

        guard shouldPreserveExistingChats else { return mergedRefreshed }

        let refreshedIDs = Set(refreshedChats.map(\.id))
        let preservedExistingChats = existingChats.filter { !refreshedIDs.contains($0.id) }
        return mergedRefreshed + preservedExistingChats
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
            chats: [], selectedChatID: nil, chatsCursor: nil, hasMoreChats: false,
            lowPriorityChatIDs: [], lastLoadedInboxFilter: nil, chatsError: nil
        )
    }

    private func captureListState() -> ChatListState {
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

    private func restoreListState(_ state: ChatListState) {
        setChats(state.chats)
        selectedChatID = state.selectedChatID
        chatsCursor = state.chatsCursor
        hasMoreChats = state.hasMoreChats
        lowPriorityChatIDs = state.lowPriorityChatIDs
        lastLoadedInboxFilter = state.lastLoadedInboxFilter
        chatsError = state.chatsError
    }

    // MARK: - Message merging

    private func mergedMessages(existing: [Message], incoming: [Message]) -> [Message] {
        var merged = Dictionary(existing.map { ($0.timelineKey, $0) }, uniquingKeysWith: { current, _ in current })
        for message in incoming {
            merged.updateValue(message, forKey: message.timelineKey)
        }
        return merged.values.sorted(by: { $0.numericSortKey < $1.numericSortKey })
    }

    private func refreshedMessages(existing: [Message], latestPage: [Message]) -> [Message] {
        let normalizedLatestMessages = normalizedMessages(latestPage)
        guard let oldestLatestSortKey = normalizedLatestMessages.first?.sortKey else {
            return existing
        }
        let oldestLatestNumeric = Int64(oldestLatestSortKey) ?? 0
        let preservedOlderMessages = existing.filter { $0.numericSortKey < oldestLatestNumeric }
        return mergedMessages(existing: preservedOlderMessages, incoming: normalizedLatestMessages)
    }

    private func normalizedMessages(_ messages: [Message]) -> [Message] {
        var byTimelineKey: [String: Message] = [:]
        for message in messages {
            byTimelineKey.updateValue(message, forKey: message.timelineKey)
        }
        return byTimelineKey.values.sorted(by: { $0.numericSortKey < $1.numericSortKey })
    }

    // MARK: - Errors

    private func handleMessageError(_ error: any Error) {
        if isCancellationLikeError(error) { return }
        messagesError = error.localizedDescription
    }

    private func handleMessageError(message: String) {
        messagesError = message
    }

    private func isCancellationLikeError(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return true }
        return error.localizedDescription.localizedStandardContains("cancelled")
            || error.localizedDescription.localizedStandardContains("canceled")
    }
}
