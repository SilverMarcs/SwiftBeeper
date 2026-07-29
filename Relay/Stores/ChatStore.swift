import Foundation
import Observation

enum InboxFilter: String, CaseIterable {
    case primary
    case lowPriority = "low-priority"
    case archive
    case unread

    var label: String {
        switch self {
        case .primary: "Primary"
        case .lowPriority: "Low Priority"
        case .archive: "Archive"
        case .unread: "Unread"
        }
    }

    var systemImage: String {
        switch self {
        case .primary: "tray.full"
        case .lowPriority: "tray"
        case .archive: "archivebox"
        case .unread: "envelope.badge"
        }
    }
}

enum ChatFilter: Hashable, Equatable, Identifiable {
    case inbox(InboxFilter)
    case service(serviceID: String, name: String)

    var id: String {
        switch self {
        case .inbox(let inbox): return "inbox_\(inbox.rawValue)"
        case .service(let id, _): return "service_\(id)"
        }
    }

    var label: String {
        switch self {
        case .inbox(let inbox): return inbox.label
        case .service(_, let name): return name
        }
    }

    var systemImage: String {
        switch self {
        case .inbox(let inbox): return inbox.systemImage
        case .service(let serviceID, _):
            return Self.systemImage(for: serviceID)
        }
    }

    static func systemImage(for serviceID: String) -> String {
        let id = serviceID.lowercased()
        if id.contains("whatsapp") { return "phone.bubble.fill" }
        if id.contains("telegram") { return "paperplane.fill" }
        if id.contains("signal") { return "envelope.badge.shield.half.filled" }
        if id.contains("discord") { return "gamecontroller.fill" }
        if id.contains("slack") { return "square.grid.3x3.topleft.filled" }
        if id.contains("instagram") { return "camera.fill" }
        if id.contains("facebook") || id.contains("messenger") { return "bubble.left.and.bubble.right.fill" }
        if id.contains("linkedin") { return "person.text.rectangle.fill" }
        if id.contains("twitter") || id.contains("x") { return "x.squareroot" }
        if id.contains("gmessages") || id.contains("google messages") { return "message.fill" }
        if id.contains("hungryserv") || id.contains("matrix") { return "circle.grid.hex.fill" }
        return "bubble.left.and.bubble.right"
    }

    static func cleanNetworkName(for serviceID: String) -> String {
        let clean = serviceID.replacingOccurrences(of: "go", with: "")
                            .replacingOccurrences(of: "local-", with: "")
        switch clean.lowercased() {
        case "whatsapp": return "WhatsApp"
        case "telegram": return "Telegram"
        case "signal": return "Signal"
        case "discord": return "Discord"
        case "slack": return "Slack"
        case "linkedin": return "LinkedIn"
        case "instagram": return "Instagram"
        case "facebook", "messenger": return "Messenger"
        case "gmessages": return "Google Messages"
        case "gvoice": return "Google Voice"
        case "twitter", "x": return "Twitter/X"
        case "imessage": return "iMessage"
        case "hungryserv": return "Beeper (Matrix)"
        default:
            return clean.capitalized
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
    var selectedFilter: ChatFilter = .inbox(.primary)
    var selectedInboxFilter: InboxFilter {
        get {
            switch selectedFilter {
            case .inbox(let inbox): return inbox
            case .service: return .primary
            }
        }
        set {
            selectedFilter = .inbox(newValue)
        }
    }
    private(set) var connectedAccounts: [Account] = []

    /// The logged-in user as they appear across their chats. There is no
    /// dedicated "me" endpoint — the backend only surfaces the current user as
    /// the `isSelf` participant inside each chat — so pick the first such
    /// participant that carries a usable name/avatar, falling back to any.
    var currentUserProfile: ChatParticipant? {
        let selves = chats.compactMap { $0.participants?.items.first(where: { $0.isSelf == true }) }
        return selves.first(where: { ($0.fullName?.isEmpty == false) || ($0.username?.isEmpty == false) }) ?? selves.first
    }

    var isArchiveSelected: Bool {
        if case .inbox(.archive) = selectedFilter {
            return true
        }
        return false
    }
    
    var availableServiceFilters: [ChatFilter] {
        if !connectedAccounts.isEmpty {
            return connectedAccounts.compactMap { account in
                guard account.accountID != "hungryserv" else { return .service(serviceID: "hungryserv", name: "Beeper (Matrix)") }
                let name = account.network ?? ChatFilter.cleanNetworkName(for: account.accountID)
                return .service(serviceID: account.accountID, name: name)
            }
        } else {
            let fallbackServices = [
                ("whatsapp", "WhatsApp"),
                ("telegram", "Telegram"),
                ("facebookgo", "Messenger"),
                ("instagramgo", "Instagram"),
                ("signal", "Signal"),
                ("discordgo", "Discord"),
                ("slackgo", "Slack"),
                ("linkedin", "LinkedIn"),
                ("gmessages", "Google Messages"),
                ("gvoice", "Google Voice"),
                ("twitter", "Twitter/X"),
                ("imessage", "iMessage")
            ]
            return fallbackServices.map { .service(serviceID: $0.0, name: $0.1) }
        }
    }
    var searchQuery: String = ""
    var searchResults: [Chat]?
    var isSearching = false
    private var chatsCursor: String?
    private var lastLoadedInboxFilter: InboxFilter?
    private var chatsByID: [String: Chat] = [:]

    var selectedChatID: String? {
        didSet {
            guard oldValue != selectedChatID else { return }
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
                loadMessagesTask = Task { [weak self] in await self?.loadMessages(for: chatID) }
            } else {
                loadMessagesTask = nil
            }
        }
    }

    // MARK: Open-chat timeline

    private(set) var messages: [Message] = [] {
        didSet {
            // Cache the displayable subset (and bump a cheap version counter) on
            // write rather than re-deriving it on every `messages(for:)` call.
            // `isDisplayable` lowercases free text to sniff membership events, so
            // filtering in the view's `body` re-scanned the whole timeline on
            // every unrelated store change (a sidebar refresh re-runs the open
            // chat's body). The guarded writes here only fire on real change, so
            // this recompute is bounded to actual timeline mutations.
            displayableMessages = messages.filter(\.isDisplayable)
            messagesVersion &+= 1
        }
    }
    /// Displayable subset of `messages`, recomputed only when `messages` changes.
    private(set) var displayableMessages: [Message] = []
    /// Monotonic counter bumped on every `messages` change. Lets views key their
    /// timeline memoization on an O(1) value instead of deep-comparing `[Message]`.
    private(set) var messagesVersion: Int = 0
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
        let baseChats = searchQuery.isBlank ? chats : (searchResults ?? chats)
        switch selectedFilter {
        case .inbox:
            return baseChats
        case .service(let serviceID, _):
            return baseChats.filter { chat in
                guard let chatAccountID = chat.accountID else { return false }
                let target = serviceID.lowercased()
                let actual = chatAccountID.lowercased()
                return actual == target || actual.contains(target) || target.contains(actual)
            }
        }
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
        chat.isLowPriority != true && chat.isArchived != true
    }

    // MARK: - Open-chat accessors

    func messages(for chatID: String) -> [Message] {
        guard chatID == messagesChatID else { return [] }
        return displayableMessages
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
        await loadConnectedAccounts()
        realtimeService.start()
    }

    func loadConnectedAccounts() async {
        guard !APIClient.accessToken.isEmpty else { return }
        do {
            connectedAccounts = try await APIClient.listAccounts()
        } catch {
            // Non-critical; the service-filter list falls back to defaults.
        }
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

    func handleAppBackground() {
        realtimeService.stop()
    }

    func clearState() {
        restoreListState(.empty)
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
            let response = try await APIClient.listChats(inbox: selectedInboxFilter.rawValue)
            let refreshedChats = response.items
            let refreshedCursor = response.oldestCursor
            let refreshedHasMoreChats = response.hasMore ?? false

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

            // macOS/iPad auto-select the first chat (and on launch / filter
            // change); iPhone navigation is manual, so leave it unselected.
            if selectedChatID == snapshot.selectedChatID {
                if let existingSelectedChatID = snapshot.selectedChatID, chatsByID[existingSelectedChatID] != nil {
                    selectedChatID = existingSelectedChatID
                } else if chatsByID[selectedChatID ?? ""] == nil {
                    selectedChatID = autoSelectedChatID
                }
            } else if chatsByID[selectedChatID ?? ""] == nil {
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

            let response = try await APIClient.listChats(
                inbox: selectedInboxFilter.rawValue,
                cursor: cursor,
                direction: "before"
            )
            let newChats = response.items.filter { !existingIDs.contains($0.id) }
            setChats(chats + newChats)
            chatsCursor = response.oldestCursor
            hasMoreChats = response.hasMore ?? false
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
            return
        }

        let requestID = UUID()
        latestLoadRequestID = requestID
        isLoadingMessages = true
        defer {
            if latestLoadRequestID == requestID { isLoadingMessages = false }
        }

        do {
            let response = try await APIClient.listMessages(chatID: chatID)
            guard latestLoadRequestID == requestID, chatID == selectedChatID else {
                return
            }

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
            guard latestLoadRequestID == requestID else { return }
            handleMessageError(error)
        }
    }

    /// Awaitable handle for the store-owned open-chat load, so the detail view can
    /// sequence its scroll/unread UI without owning the request's lifetime.
    func awaitCurrentMessagesLoad() async {
        await loadMessagesTask?.value
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

    nonisolated func realtimeDidUpsertChat(chatID: String?, chat: Chat?) {
        Task { @MainActor in
            if let chat {
                applyChatUpsert(chat)
            } else {
                scheduleChatsRefresh()
            }
        }
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
                //
                // The sidebar (preview, unread, ordering) is updated by the
                // `chat.upserted` event that always accompanies a message — now
                // hydrated with the chat summary — so we no longer refetch the
                // whole chat list here.
                applyIncomingMessages(incoming, chatID: chatID)
                scheduleMessagesRefresh(chatID: chatID)
            } else {
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

    /// Applies a hydrated `chat.upserted` summary to the sidebar without a full
    /// list refetch. Patches the chat in place and re-sorts by recency for the
    /// common case (an existing chat that still belongs to the open inbox got new
    /// activity). Falls back to a debounced list refresh only when we lack the
    /// context to patch locally — a brand-new chat, or one whose inbox membership
    /// changed (archived/unarchived, low-priority toggled, etc.).
    private func applyChatUpsert(_ incoming: Chat) {
        // Keep an in-flight search view consistent if it holds this chat.
        if var results = searchResults,
           let index = results.firstIndex(where: { $0.id == incoming.id }) {
            results[index] = results[index].merging(detail: incoming)
            searchResults = results
        }

        let belongs = chatBelongsToCurrentInbox(incoming)

        guard chatsByID[incoming.id] != nil else {
            // A chat we don't have yet. We lack list context (cursor position,
            // ordering against unloaded pages), so let the server place it.
            if belongs { scheduleChatsRefresh() }
            return
        }

        guard belongs else {
            // The chat left the current inbox (archived, marked low-priority,
            // read, …). Let the server reconcile membership authoritatively.
            scheduleChatsRefresh()
            return
        }

        var updated = chats
        if let index = updated.firstIndex(where: { $0.id == incoming.id }) {
            updated[index] = updated[index].merging(detail: incoming)
        }
        // The backend orders chats by activity (sorting_timestamp DESC); mirror
        // that so a freshly-active chat moves to the top of the sidebar.
        updated.sort { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
        setChats(updated)
    }

    /// Whether a chat belongs to the currently-loaded inbox, mirroring the
    /// backend's inbox filtering. Used to decide whether a `chat.upserted` can be
    /// patched locally or needs a server-authoritative refetch. The `unread`
    /// inbox also keys off marked-unread state, which the client model doesn't
    /// carry, so we always refetch there to stay correct.
    private func chatBelongsToCurrentInbox(_ chat: Chat) -> Bool {
        switch selectedInboxFilter {
        case .primary: return chat.isArchived != true && chat.isLowPriority != true
        case .lowPriority: return chat.isLowPriority == true
        case .archive: return chat.isArchived == true
        case .unread: return false
        }
    }

    /// Posts notifications for a background chat directly from the realtime payload.
    private func notify(_ incoming: [Message], chatID: String) async {
        guard let chat = chat(byID: chatID), chat.isMuted != true, isPrimaryInboxChat(chat) else { return }

        for message in incoming {
            if message.isOutgoing(in: chat) || message.isMembershipEvent || message.isReaction { continue }
            if Date().timeIntervalSince(message.timestamp) > 60 { continue }
            if message.id == lastNotifiedMessageIDByChatID[chatID] { continue }
            lastNotifiedMessageIDByChatID[chatID] = message.id
            notificationService.postNewMessageNotification(message: message, chat: chat)
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
        var lastLoadedInboxFilter: InboxFilter?
        var chatsError: String?

        static let empty = ChatListState(
            chats: [], selectedChatID: nil, chatsCursor: nil, hasMoreChats: false,
            lastLoadedInboxFilter: nil, chatsError: nil
        )
    }

    private func captureListState() -> ChatListState {
        ChatListState(
            chats: chats,
            selectedChatID: selectedChatID,
            chatsCursor: chatsCursor,
            hasMoreChats: hasMoreChats,
            lastLoadedInboxFilter: lastLoadedInboxFilter,
            chatsError: chatsError
        )
    }

    private func restoreListState(_ state: ChatListState) {
        setChats(state.chats)
        selectedChatID = state.selectedChatID
        chatsCursor = state.chatsCursor
        hasMoreChats = state.hasMoreChats
        lastLoadedInboxFilter = state.lastLoadedInboxFilter
        chatsError = state.chatsError
    }

    // MARK: - Message merging

    private func mergedMessages(existing: [Message], incoming: [Message]) -> [Message] {
        var merged = Dictionary(existing.map { ($0.timelineKey, $0) }, uniquingKeysWith: { current, _ in current })
        for message in incoming {
            if let existingMsg = merged[message.timelineKey] {
                merged[message.timelineKey] = existingMsg.merging(detail: message)
            } else {
                merged[message.timelineKey] = message
            }
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
