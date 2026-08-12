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

    var accountIDs: [String] {
        guard case .service(let serviceID, _) = self else { return [] }
        return [serviceID]
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
}

/// The app's single source of truth: chat list, the open chat's timeline, the
/// composer, and realtime event handling. The timeline is *event-sourced* — the
/// backend hydrates each `message.upserted` event with the full message, so we
/// apply it directly instead of refetching. Only reconnects, sequence gaps, and
/// unhydrated events recover from REST snapshots.
@MainActor
@Observable
final class ChatStore: RealtimeEventHandler {
    private let realtimeService: RealtimeService
    private let notificationService: NotificationService
    @ObservationIgnored private let cache: ChatCache
    @ObservationIgnored private var cacheSnapshot = ChatCacheSnapshot.empty
    @ObservationIgnored private var activeCacheIdentity: String?
    @ObservationIgnored private var cacheSaveTask: Task<Void, Never>?

    // MARK: Chat list

    private(set) var chats: [Chat] = []
    private(set) var hasMoreChats = false
    private(set) var isLoadingMoreChats = false
    private(set) var isLoadingChats = false
    private(set) var chatsError: String?
    private(set) var chatsErrorIsAuth: Bool = false
    private(set) var isRecoveringAuth: Bool = false
    var selectedFilter: ChatFilter = .inbox(.primary) {
        didSet {
            guard oldValue.id != selectedFilter.id else { return }
            activateCachedChatList(for: selectedFilter.id)
        }
    }
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
    private(set) var currentUserProfile: ChatParticipant?

    var isArchiveSelected: Bool {
        if case .inbox(.archive) = selectedFilter {
            return true
        }
        return false
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
    var searchQuery: String = ""
    var searchResults: [Chat]?
    var isSearching = false
    private var chatsCursor: String?
    private var lastLoadedFilterID: String?
    private var chatsByID: [String: Chat] = [:]

    var selectedChatID: String? {
        didSet {
            guard oldValue != selectedChatID else { return }
            cacheCurrentTimeline()

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
                activateCachedTimeline(for: chatID)
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
    /// New messages use independent optimistic outbox items; edits still use a
    /// blocking request and temporarily lock the composer.
    private(set) var isSavingEdit = false
    var messagesError: String?

    // MARK: Composer / outbox

    var replyingToMessage: Message?
    var editingMessage: Message?
    private(set) var outgoingMessagesByChatID: [String: [OutgoingMessage]] = [:]
    @ObservationIgnored private var outgoingSendTasks: [OutgoingMessage.ID: Task<Void, Never>] = [:]

    var activeComposerMessage: Message? {
        editingMessage ?? replyingToMessage
    }

    // MARK: Realtime / notifications

    private var scheduledChatsRefreshTask: Task<Void, Never>?
    private var scheduledMessagesRefreshTask: Task<Void, Never>?
    private var loadMessagesTask: Task<Void, Never>?
    private var lastNotifiedMessageIDByChatID: [String: String] = [:]

    init(
        realtimeService: RealtimeService,
        notificationService: NotificationService,
        cache: ChatCache = ChatCache()
    ) {
        self.realtimeService = realtimeService
        self.notificationService = notificationService
        self.cache = cache
        realtimeService.eventHandler = self
    }

    /// Convenience for previews and tests.
    convenience init() {
        self.init(realtimeService: RealtimeService(), notificationService: NotificationService())
    }

    // MARK: - Derived chat-list accessors

    var displayedChats: [Chat] {
        searchQuery.isBlank ? chats : (searchResults ?? chats)
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
        let outgoingMessages = outgoingMessagesByChatID[chatID, default: []]
        guard !outgoingMessages.isEmpty else { return displayableMessages }
        return displayableMessages.filter { message in
            !outgoingMessages.contains { $0.suppressesConfirmedMessage(message) }
        }
    }

    func outgoingMessages(for chatID: String) -> [OutgoingMessage] {
        outgoingMessagesByChatID[chatID] ?? []
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

        let previousAccessToken = APIClient.accessToken
        let previousCacheIdentity = activeCacheIdentity
        APIClient.accessToken = accessToken

        if accessToken.isEmpty {
            realtimeService.stop()
            selectedChatID = nil
            clearState()
            if let previousCacheIdentity {
                await cache.remove(endpointIdentity: previousCacheIdentity)
            }
            return
        }

        let cacheIdentity = APIConfiguration.endpointIdentity
        activeCacheIdentity = cacheIdentity

        // A direct non-empty token replacement can represent a different user
        // on the same endpoint. Do not briefly expose the previous user's cache.
        if previousAccessToken.isEmpty {
            let restoredSnapshot = await cache.load(endpointIdentity: cacheIdentity)
            guard APIClient.accessToken == accessToken, !Task.isCancelled else { return }
            cacheSnapshot = restoredSnapshot
            activateCachedChatList(for: selectedFilter.id)
        } else {
            clearState()
            activeCacheIdentity = cacheIdentity
            if let previousCacheIdentity {
                await cache.remove(endpointIdentity: previousCacheIdentity)
            }
        }

        await loadChats()
        await loadSession()
        realtimeService.start()
    }

    func loadSession() async {
        guard !APIClient.accessToken.isEmpty else { return }
        do {
            let session = try await APIClient.getSession()
            currentUserProfile = session.user
            connectedAccounts = session.accounts
        } catch {
            // Non-critical; chat and realtime loading remain usable.
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
        persistCacheImmediately()
    }

    func handleAppActivation(_ isActive: Bool) {
        realtimeService.setAppIsActive(isActive)
    }

    func clearState() {
        cacheSaveTask?.cancel()
        cacheSaveTask = nil
        cacheSnapshot = .empty
        activeCacheIdentity = nil
        restoreListState(.empty)
        connectedAccounts = []
        currentUserProfile = nil
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
        for task in outgoingSendTasks.values {
            task.cancel()
        }
        outgoingSendTasks = [:]
        outgoingMessagesByChatID = [:]
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
        let requestedFilter = selectedFilter
        let shouldPreserveExistingChats = lastLoadedFilterID == requestedFilter.id
        let tokenAtStart = APIClient.accessToken

        isLoadingChats = true
        defer { isLoadingChats = false }

        do {
            let response = try await APIClient.listChats(
                inbox: selectedInboxFilter.rawValue,
                accountIDs: requestedFilter.accountIDs
            )
            guard selectedFilter.id == requestedFilter.id else { return }
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
            lastLoadedFilterID = requestedFilter.id

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
            cacheCurrentChatList()
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
            let requestedFilter = selectedFilter
            let existingIDs = Set(chats.map(\.id))

            let response = try await APIClient.listChats(
                inbox: selectedInboxFilter.rawValue,
                accountIDs: requestedFilter.accountIDs,
                cursor: cursor,
                direction: "before"
            )
            guard selectedFilter.id == requestedFilter.id else { return }
            let newChats = response.items.filter { !existingIDs.contains($0.id) }
            setChats(chats + newChats)
            chatsCursor = response.oldestCursor
            hasMoreChats = response.hasMore ?? false
            cacheCurrentChatList()
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
            let requestedFilter = selectedFilter
            let response = try await APIClient.searchChats(
                query: trimmed,
                inbox: selectedInboxFilter.rawValue,
                accountIDs: requestedFilter.accountIDs
            )
            guard selectedFilter.id == requestedFilter.id, searchQuery.trimmed == trimmed else { return }
            searchResults = response.items
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
        cacheCurrentChatList()
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
            cacheCurrentChatList()
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

    /// Full-refreshes the open chat's timeline on first appearance, reconnect,
    /// or realtime sequence recovery. Steady-state mutations arrive via events.
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

            // Recovery snapshots may equal state already applied from realtime.
            // Avoid no-op Observation writes that would re-render the timeline.
            if messagesError != nil { messagesError = nil }
            if let readKey = response.lastReadByOtherSortKey, readKey != lastReadByOtherSortKey {
                lastReadByOtherSortKey = readKey
            }
            let existing = messagesChatID == chatID ? messages : []
            let merged = refreshedMessages(existing: existing, latestPage: response.items)
            if merged != messages { messages = merged }
            reconcileOutgoingMessages(with: response.items, chatID: chatID)
            if messagesChatID != chatID { messagesChatID = chatID }
            if hasMoreOlderMessages != response.hasMore { hasMoreOlderMessages = response.hasMore }
            cacheCurrentTimeline()
        } catch {
            guard latestLoadRequestID == requestID else { return }
            handleMessageError(error)
        }
    }

    /// Whether a server or cache snapshot is already available for this chat.
    func hasLoadedTimeline(for chatID: String) -> Bool {
        messagesChatID == chatID
    }

    /// Cached timelines return immediately so views can lay them out while the
    /// store-owned network refresh continues in the background.
    func awaitInitialMessages(for chatID: String) async {
        guard !hasLoadedTimeline(for: chatID) else { return }
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
            cacheCurrentTimeline()
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
        cacheCurrentTimeline()
    }

    /// Assigns each canonical message to at most one optimistic row. Transaction
    /// IDs are preferred; content matching covers the narrow WS-before-REST race.
    private func reconcileOutgoingMessages(with incoming: [Message], chatID: String) {
        guard var outgoing = outgoingMessagesByChatID[chatID], !outgoing.isEmpty else { return }

        for message in incoming where message.isSender == true {
            guard let index = outgoing.firstIndex(where: {
                !$0.confirmedMessageIDs.contains(message.id) && $0.matchesConfirmedMessage(message)
            }) else { continue }

            outgoing[index].confirmedMessageIDs.insert(message.id)
            if outgoing[index].confirmedMessageIDs.count >= outgoing[index].expectedConfirmationCount {
                outgoing.remove(at: index)
            }
        }

        outgoingMessagesByChatID[chatID] = outgoing.isEmpty ? nil : outgoing
    }

    // MARK: - Sending / editing

    /// Adds a message to the outbox synchronously so the timeline can display it
    /// before any upload or remote-server request begins.
    @discardableResult
    func sendMessage(text: String, attachments: [PendingAttachment], to chatID: String) -> Bool {
        guard !APIClient.accessToken.isEmpty else { return false }

        let trimmedText = text.trimmed
        let hasText = !trimmedText.isEmpty
        guard hasText || !attachments.isEmpty else { return false }

        let outgoing = OutgoingMessage(
            chatID: chatID,
            text: hasText ? trimmedText : "",
            attachments: attachments,
            replyToMessageID: replyingToMessage?.id
        )
        outgoingMessagesByChatID[chatID, default: []].append(outgoing)
        replyingToMessage = nil
        messagesError = nil
        startSending(outgoing)
        return true
    }

    func retrySending(_ messageID: OutgoingMessage.ID) {
        guard let outgoing = outgoingMessage(withID: messageID),
              case .failed = outgoing.state,
              !APIClient.accessToken.isEmpty else { return }

        updateOutgoingMessage(messageID) { message in
            message.state = .sending
            message.uploadProgressByAttachmentID = [:]
            message.pendingMessageIDs = []
            message.confirmedMessageIDs = []
        }
        startSending(outgoing)
    }

    private func startSending(_ outgoing: OutgoingMessage) {
        outgoingSendTasks[outgoing.id]?.cancel()
        outgoingSendTasks[outgoing.id] = Task { [weak self] in
            await self?.transmit(outgoing)
        }
    }

    private func transmit(_ outgoing: OutgoingMessage) async {
        defer { outgoingSendTasks[outgoing.id] = nil }
        do {
            let firstAttachmentInput = try await uploadAttachment(outgoing.attachments.first, for: outgoing.id)
            let firstResponse = try await APIClient.sendMessage(
                chatID: outgoing.chatID,
                text: outgoing.text.isEmpty ? nil : outgoing.text,
                replyToMessageID: outgoing.replyToMessageID,
                attachment: firstAttachmentInput
            )
            recordPendingMessageID(firstResponse.pendingMessageID, for: outgoing.id)

            for attachment in outgoing.attachments.dropFirst() {
                let attachmentInput = try await uploadAttachment(attachment, for: outgoing.id)
                let response = try await APIClient.sendMessage(
                    chatID: outgoing.chatID,
                    text: nil,
                    attachment: attachmentInput
                )
                recordPendingMessageID(response.pendingMessageID, for: outgoing.id)
            }
        } catch {
            guard !isCancellationLikeError(error) else { return }
            updateOutgoingMessage(outgoing.id) { message in
                message.state = .failed(error.localizedDescription)
            }
        }
    }

    private func uploadAttachment(
        _ attachment: PendingAttachment?,
        for outgoingMessageID: OutgoingMessage.ID
    ) async throws -> MessageAttachmentInput? {
        guard let attachment else { return nil }

        updateUploadProgress(0, attachmentID: attachment.id, messageID: outgoingMessageID)
        let uploadAttachment = await ImageAttachmentPreparer.prepare(attachment)
        recordUploadMetadata(uploadAttachment, originalAttachmentID: attachment.id, messageID: outgoingMessageID)
        let uploadResult = try await APIClient.uploadAsset(
            fileData: uploadAttachment.fileData,
            fileName: uploadAttachment.fileName,
            mimeType: uploadAttachment.mimeType,
            onProgress: { [weak self] progress in
                self?.updateUploadProgress(progress, attachmentID: attachment.id, messageID: outgoingMessageID)
            }
        )

        if let error = uploadResult.error, !error.isEmpty {
            throw UploadError.serverError(error)
        }

        updateUploadProgress(1, attachmentID: attachment.id, messageID: outgoingMessageID)

        var size: AttachmentSizeInput?
        if let w = uploadResult.width, let h = uploadResult.height {
            size = AttachmentSizeInput(width: w, height: h)
        }

        return MessageAttachmentInput(
            uploadID: uploadResult.uploadID,
            mimeType: uploadAttachment.mimeType,
            fileName: uploadAttachment.fileName,
            size: size,
            duration: uploadResult.duration,
            type: nil
        )
    }

    private func outgoingMessage(withID messageID: OutgoingMessage.ID) -> OutgoingMessage? {
        for messages in outgoingMessagesByChatID.values {
            if let message = messages.first(where: { $0.id == messageID }) {
                return message
            }
        }
        return nil
    }

    private func updateOutgoingMessage(
        _ messageID: OutgoingMessage.ID,
        update: (inout OutgoingMessage) -> Void
    ) {
        guard let chatID = outgoingMessagesByChatID.first(where: { _, messages in
            messages.contains(where: { $0.id == messageID })
        })?.key,
        var messages = outgoingMessagesByChatID[chatID],
        let index = messages.firstIndex(where: { $0.id == messageID }) else { return }

        update(&messages[index])
        outgoingMessagesByChatID[chatID] = messages
    }

    private func updateUploadProgress(
        _ progress: Double,
        attachmentID: PendingAttachment.ID,
        messageID: OutgoingMessage.ID
    ) {
        updateOutgoingMessage(messageID) { message in
            message.uploadProgressByAttachmentID[attachmentID] = min(max(progress, 0), 1)
        }
    }

    private func recordPendingMessageID(_ pendingMessageID: String, for messageID: OutgoingMessage.ID) {
        guard !pendingMessageID.isEmpty else { return }
        updateOutgoingMessage(messageID) { message in
            message.pendingMessageIDs.insert(pendingMessageID)
        }
    }

    private func recordUploadMetadata(
        _ attachment: PendingAttachment,
        originalAttachmentID: PendingAttachment.ID,
        messageID: OutgoingMessage.ID
    ) {
        updateOutgoingMessage(messageID) { message in
            message.uploadFileNameByAttachmentID[originalAttachmentID] = attachment.fileName
            message.uploadMimeTypeByAttachmentID[originalAttachmentID] = attachment.mimeType
        }
    }

    private func removeOutgoingMessage(_ messageID: OutgoingMessage.ID, from chatID: String) {
        outgoingMessagesByChatID[chatID]?.removeAll { $0.id == messageID }
        if outgoingMessagesByChatID[chatID]?.isEmpty == true {
            outgoingMessagesByChatID[chatID] = nil
        }
    }

    private enum UploadError: LocalizedError {
        case serverError(String)

        var errorDescription: String? {
            switch self {
            case .serverError(let message):
                return "Upload failed: \(message)"
            }
        }
    }

    func setReplyTo(_ message: Message?) {
        if message != nil { editingMessage = nil }
        replyingToMessage = message
    }

    func canEdit(_ message: Message, in chat: Chat) -> Bool {
        guard !message.isDeletedMessage, message.isOutgoing(in: chat) else { return false }
        if let accountID = chat.accountID,
           connectedAccounts.first(where: { $0.accountID == accountID })?.capabilities.unlimitedMessageEdits == true {
            return true
        }
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

        isSavingEdit = true
        defer { isSavingEdit = false }

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

    nonisolated func realtimeDidConnect(requiresResync: Bool) {
        Task { @MainActor in
            guard requiresResync else { return }
            scheduleChatsRefresh()
            if let chatID = selectedChatID {
                scheduleMessagesRefresh(chatID: chatID)
            }
        }
    }

    nonisolated func realtimeNeedsResync() {
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
            guard let chatID else {
                realtimeNeedsResync()
                return
            }

            reconcileOutgoingMessages(with: incoming, chatID: chatID)

            if chatID == selectedChatID {
                // Hydrated events are authoritative. Edits and reactions target
                // the original message ID, so the normal merge updates in place.
                applyIncomingMessages(incoming, chatID: chatID)
            } else {
                await notify(incoming, chatID: chatID)
            }
        }
    }

    nonisolated func realtimeDidUpdateReceipt(chatID: String?, entries: [[String: String]]?) {
        Task { @MainActor in
            guard let chatID, chatID == selectedChatID,
                  let readKey = entries?.first?["lastReadByOtherSortKey"] else { return }
            lastReadByOtherSortKey = readKey
            cacheCurrentTimeline()
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
    /// list refetch. The hydrated summary contains every field needed to decide
    /// filter membership, patch or remove the row, and restore server ordering.
    private func applyChatUpsert(_ incoming: Chat) {
        // Keep an in-flight search view consistent if it holds this chat.
        if var results = searchResults,
           let index = results.firstIndex(where: { $0.id == incoming.id }) {
            results[index] = results[index].merging(detail: incoming)
            searchResults = results
        }

        guard chatBelongsToCurrentFilter(incoming) else {
            removeChatLocally(incoming.id)
            return
        }

        var updated = chats
        if let index = updated.firstIndex(where: { $0.id == incoming.id }) {
            updated[index] = updated[index].merging(detail: incoming)
        } else {
            updated.append(incoming)
        }
        // The backend orders chats by activity (sorting_timestamp DESC); mirror
        // that so a freshly-active chat moves to the top of the sidebar.
        updated.sort { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
        setChats(updated)
        cacheCurrentChatList()
    }

    /// Mirrors server inbox and exact account filtering for hydrated events.
    private func chatBelongsToCurrentFilter(_ chat: Chat) -> Bool {
        if case .service(let accountID, _) = selectedFilter,
           chat.accountID != accountID {
            return false
        }
        switch selectedInboxFilter {
        case .primary: return chat.isArchived != true && chat.isLowPriority != true
        case .lowPriority: return chat.isLowPriority == true
        case .archive: return chat.isArchived == true
        case .unread: return chat.unreadCount > 0 || chat.isMarkedUnread == true
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

    // MARK: - Durable cache

    private func activateCachedChatList(for filterID: String) {
        guard let cachedList = cacheSnapshot.chatListsByFilterID[filterID] else {
            setChats([])
            chatsCursor = nil
            hasMoreChats = false
            lastLoadedFilterID = nil
            selectedChatID = nil
            return
        }

        chatsCursor = cachedList.cursor
        hasMoreChats = cachedList.hasMore
        lastLoadedFilterID = filterID
        chatsError = nil
        chatsErrorIsAuth = false
        setChats(cachedList.chats)

        if let selectedChatID, chatsByID[selectedChatID] != nil {
            self.selectedChatID = selectedChatID
        } else {
            selectedChatID = autoSelectedChatID
        }
    }

    private func activateCachedTimeline(for chatID: String) {
        guard let cachedTimeline = cacheSnapshot.timelinesByChatID[chatID] else { return }

        messages = cachedTimeline.messages
        messagesChatID = chatID
        hasMoreOlderMessages = cachedTimeline.hasMore
        lastReadByOtherSortKey = cachedTimeline.lastReadByOtherSortKey

        cacheSnapshot.timelinesByChatID[chatID] = CachedChatTimeline(
            chatID: chatID,
            messages: cachedTimeline.messages,
            hasMore: cachedTimeline.hasMore,
            lastReadByOtherSortKey: cachedTimeline.lastReadByOtherSortKey,
            updatedAt: .now
        )
        scheduleCacheSave()
    }

    private func cacheCurrentChatList() {
        guard activeCacheIdentity != nil,
              lastLoadedFilterID == selectedFilter.id else { return }

        let retainedChats = Array(chats.prefix(500))
        cacheSnapshot.chatListsByFilterID[selectedFilter.id] = CachedChatList(
            filterID: selectedFilter.id,
            chats: retainedChats,
            cursor: retainedChats.count == chats.count ? chatsCursor : nil,
            hasMore: retainedChats.count == chats.count ? hasMoreChats : false,
            updatedAt: .now
        )
        trimCachedChatListsIfNeeded()
        scheduleCacheSave()
    }

    private func cacheCurrentTimeline() {
        guard activeCacheIdentity != nil, let chatID = messagesChatID else { return }

        let retainedMessages = Array(messages.suffix(100))
        cacheSnapshot.timelinesByChatID[chatID] = CachedChatTimeline(
            chatID: chatID,
            messages: retainedMessages,
            hasMore: hasMoreOlderMessages || retainedMessages.count < messages.count,
            lastReadByOtherSortKey: lastReadByOtherSortKey,
            updatedAt: .now
        )
        trimCachedTimelinesIfNeeded()
        scheduleCacheSave()
    }

    private func trimCachedChatListsIfNeeded() {
        guard cacheSnapshot.chatListsByFilterID.count > 12 else { return }
        let expiredIDs = cacheSnapshot.chatListsByFilterID.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .dropFirst(12)
            .map(\.filterID)
        for filterID in expiredIDs {
            cacheSnapshot.chatListsByFilterID[filterID] = nil
        }
    }

    private func trimCachedTimelinesIfNeeded() {
        guard cacheSnapshot.timelinesByChatID.count > 20 else { return }
        let expiredIDs = cacheSnapshot.timelinesByChatID.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .dropFirst(20)
            .map(\.chatID)
        for chatID in expiredIDs {
            cacheSnapshot.timelinesByChatID[chatID] = nil
        }
    }

    private func scheduleCacheSave() {
        cacheSaveTask?.cancel()
        cacheSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, !Task.isCancelled,
                  let cacheIdentity = self.activeCacheIdentity else { return }
            let snapshot = self.cacheSnapshot
            await self.cache.save(snapshot, endpointIdentity: cacheIdentity)
        }
    }

    private func persistCacheImmediately() {
        cacheSaveTask?.cancel()
        cacheSaveTask = nil
        guard let cacheIdentity = activeCacheIdentity else { return }
        let snapshot = cacheSnapshot
        Task { [cache] in
            await cache.save(snapshot, endpointIdentity: cacheIdentity)
        }
    }

    // MARK: - Private storage helpers

    private func setChats(_ newChats: [Chat]) {
        // Skip identical commits: Observation invalidates on any write, even when
        // a reconnect snapshot is equal to the event-applied sidebar state.
        guard newChats != chats else { return }
        chats = newChats
        chatsByID = Dictionary(newChats.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        publishPrimaryInboxToWatch()
    }

    private func updateChat(_ chatID: String, _ mutate: (inout Chat) -> Void) {
        var didUpdateChat = false
        if let index = chats.firstIndex(where: { $0.id == chatID }) {
            mutate(&chats[index])
            chatsByID[chatID] = chats[index]
            didUpdateChat = true
        }
        if var results = searchResults,
           let searchIndex = results.firstIndex(where: { $0.id == chatID }) {
            mutate(&results[searchIndex])
            searchResults = results
        }
        if didUpdateChat {
            publishPrimaryInboxToWatch()
            cacheCurrentChatList()
        }
    }

    private func publishPrimaryInboxToWatch() {
        #if os(iOS)
        guard selectedFilter == .inbox(.primary) else { return }
        PhoneWatchConnectivityService.shared.publish(chats: chats)
        #endif
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
        var lastLoadedFilterID: String?
        var chatsError: String?

        static let empty = ChatListState(
            chats: [], selectedChatID: nil, chatsCursor: nil, hasMoreChats: false,
            lastLoadedFilterID: nil, chatsError: nil
        )
    }

    private func captureListState() -> ChatListState {
        ChatListState(
            chats: chats,
            selectedChatID: selectedChatID,
            chatsCursor: chatsCursor,
            hasMoreChats: hasMoreChats,
            lastLoadedFilterID: lastLoadedFilterID,
            chatsError: chatsError
        )
    }

    private func restoreListState(_ state: ChatListState) {
        setChats(state.chats)
        selectedChatID = state.selectedChatID
        chatsCursor = state.chatsCursor
        hasMoreChats = state.hasMoreChats
        lastLoadedFilterID = state.lastLoadedFilterID
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

    private func isCancellationLikeError(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return true }
        return error.localizedDescription.localizedStandardContains("cancelled")
            || error.localizedDescription.localizedStandardContains("canceled")
    }
}
