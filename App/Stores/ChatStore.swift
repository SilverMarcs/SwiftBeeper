import Foundation
import Observation

enum InboxFilter: String, CaseIterable {
    case primary
    case archive
    case unread

    var label: String {
        switch self {
        case .primary: "Primary"
        case .archive: "Archive"
        case .unread: "Unread"
        }
    }

    var systemImage: String {
        switch self {
        case .primary: "tray.full"
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

/// Observable UI state for the chat list, open timeline, and composer. The
/// Matrix database owns persistence; local events update the displayed values.
/// Reconnects and missed events reload the relevant pages from that database.
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
    var selectedFilter: ChatFilter = .inbox(.primary) {
        didSet {
            guard oldValue.id != selectedFilter.id else { return }
            resetSearch()
            resetChatList()
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
    var searchQuery: String = "" {
        didSet {
            guard oldValue != searchQuery else { return }
            resetSearch()
        }
    }
    var searchResults: [Chat]?
    var isSearching = false
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var latestSearchRequestID: UUID?
    private var chatsCursor: String?
    private var latestChatsRequestID: UUID?
    private var lastLoadedFilterID: String?
    private var chatsByID: [String: Chat] = [:]
    private var selectedChatSnapshot: Chat?
    @ObservationIgnored var visibleChatID: String?
    private var pendingNotificationChatID: String?
    private(set) var notificationSelectionID: UUID?
    @ObservationIgnored private var notificationChatTask: Task<Void, Never>?
    @ObservationIgnored private var notificationChatRequestID = UUID()

    /// Retain a tap through startup, sync, and a room outside the loaded sidebar.
    func openNotificationChat(_ chatID: String) {
        guard !chatID.isEmpty else { return }
        notificationChatTask?.cancel()
        notificationChatTask = nil
        notificationChatRequestID = UUID()
        pendingNotificationChatID = chatID
        searchQuery = ""
        resolveNotificationChat()
        loadPendingNotificationChat()
    }

    private func resolveNotificationChat() {
        guard notificationService.badges.isActive,
              let id = pendingNotificationChatID, chat(byID: id) != nil else { return }
        pendingNotificationChatID = nil
        selectedChatID = id
        notificationSelectionID = UUID()
    }

    private func loadPendingNotificationChat() {
        guard notificationService.badges.isActive,
              let id = pendingNotificationChatID, !APIClient.accessToken.isEmpty,
              !isLoadingChats, notificationChatTask == nil else { return }
        let token = APIClient.accessToken
        let requestID = UUID()
        notificationChatRequestID = requestID
        notificationChatTask = Task { [weak self] in
            guard let self else { return }
            defer { if notificationChatRequestID == requestID { notificationChatTask = nil } }
            do {
                let chat = try await APIClient.getChat(chatID: id)
                guard !Task.isCancelled, pendingNotificationChatID == id,
                      APIClient.accessToken == token else { return }
                applyChatUpsert(chat)
            } catch {
                // A room not yet present stays pending for its local sync event.
            }
        }
    }

    var selectedChatID: String? {
        didSet {
            guard oldValue != selectedChatID else { return }
            selectedChatSnapshot = selectedChatID.flatMap { chat(byID: $0) }
            timelineGeneration = UUID()

            // Only the open chat keeps a timeline in memory — reset it on switch.
            messages = []
            messagesChatID = nil
            olderMessagesCursor = nil
            hasMoreOlderMessages = false
            isLoadingOlderMessages = false
            lastReadByOtherSortKey = nil
            replyingToMessage = nil
            editingMessage = nil
            messagesError = nil

            // The store owns the database read so view recreation cannot cancel
            // it. A selection change cancels the previous chat's request.
            loadMessagesTask?.cancel()
            updateMessageSubscriptions()
            if let chatID = selectedChatID {
                notificationService.clearDeliveredNotifications(for: chatID)
                loadMessagesTask = Task { [weak self] in
                    guard !Task.isCancelled, self?.selectedChatID == chatID else { return }
                    await MatrixRuntime.shared.openedRoom(chatID)
                    await self?.loadMessages(for: chatID)
                }
            } else {
                loadMessagesTask = nil
                Task { await MatrixRuntime.shared.openedRoom(nil) }
            }
        }
    }

    // MARK: Open-chat timeline

    private(set) var messages: [Message] = [] {
        didSet {
            // Derive the displayable subset (and bump a cheap version counter) on
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
    private var timelineGeneration = UUID()
    private(set) var isLoadingOlderMessages = false
    private(set) var isLoadingMessages = false
    /// New messages use independent optimistic outbox items; edits still use a
    /// blocking request and temporarily lock the composer.
    private(set) var isSavingEdit = false
    var messagesError: String?

    // MARK: Composer / outbox

    var replyingToMessage: Message?
    var editingMessage: Message?
    private(set) var outgoingMessagesByChatID: [String: [OutgoingMessage]] = [:] {
        didSet { updateMessageSubscriptions() }
    }
    private var olderMessagesCursor: String?
    private var chatWindowSize = 25
    @ObservationIgnored private var outgoingSendTasks: [OutgoingMessage.ID: Task<Void, Never>] = [:]

    var activeComposerMessage: Message? {
        editingMessage ?? replyingToMessage
    }

    // MARK: Realtime / notifications

    private var scheduledChatsRefreshTask: Task<Void, Never>?
    private var scheduledMessagesRefreshTask: Task<Void, Never>?
    private var loadMessagesTask: Task<Void, Never>?

    init(
        realtimeService: RealtimeService,
        notificationService: NotificationService
    ) {
        self.realtimeService = realtimeService
        self.notificationService = notificationService
        realtimeService.eventHandler = self
    }

    /// Convenience for view previews.
    convenience init() {
        self.init(realtimeService: RealtimeService(), notificationService: NotificationService())
    }

    // MARK: - Derived chat-list accessors

    var displayedChats: [Chat] {
        searchQuery.isBlank ? chats : (searchResults ?? chats)
    }

    var selectedChat: Chat? {
        selectedChatSnapshot
    }

    /// Which chat to fall back to when the current selection becomes invalid.
    /// macOS and iPad auto-select the first chat; iPhone stays manual (nil).
    private var autoSelectedChatID: String? {
        Device.isIPhone ? nil : chats.first?.id
    }

    func chat(byID chatID: String) -> Chat? {
        if selectedChatSnapshot?.id == chatID { return selectedChatSnapshot }
        return chatsByID[chatID] ?? searchResults?.first(where: { $0.id == chatID })
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
        guard accessToken != APIClient.accessToken else { return }

        realtimeService.reset()
        APIClient.accessToken = accessToken
        notificationService.badges.configure(accessToken: accessToken)
        clearState()
        guard !accessToken.isEmpty else { return }

        await loadChats()
        guard APIClient.accessToken == accessToken else { return }
        realtimeService.start()
        await loadSession()
    }

    func loadSession() async {
        let accessToken = APIClient.accessToken
        guard !accessToken.isEmpty else { return }
        do {
            let session = try await APIClient.getSession()
            guard APIClient.accessToken == accessToken else { return }
            currentUserProfile = session.user
            connectedAccounts = session.accounts
        } catch {
            // Non-critical; chat and realtime loading remain usable.
        }
    }

    /// Resume local updates and reload the open timeline after suspension.
    func handleAppForeground() {
        #if !os(macOS)
        notificationService.badges.setActive(true)
        #endif
        resolveNotificationChat()
        loadPendingNotificationChat()
        guard !APIClient.accessToken.isEmpty else { return }
        realtimeService.start()
        if let chatID = selectedChatID {
            notificationService.clearDeliveredNotifications(for: chatID)
        }
    }

    func handleAppBackground() {
        #if !os(macOS)
        notificationService.badges.setActive(false)
        #endif
        realtimeService.stop()
    }

    /// macOS window focus clears alerts without restarting the local event stream.
    func handleAppActivation(_ isActive: Bool) {
        notificationService.badges.setActive(isActive)
        if isActive {
            resolveNotificationChat()
            loadPendingNotificationChat()
        }
        guard isActive, let chatID = selectedChatID else { return }
        notificationService.clearDeliveredNotifications(for: chatID)
    }

    func clearState() {
        notificationChatTask?.cancel()
        notificationChatTask = nil
        notificationChatRequestID = UUID()
        if APIClient.accessToken.isEmpty {
            pendingNotificationChatID = nil
            notificationSelectionID = nil
        }
        scheduledChatsRefreshTask?.cancel()
        scheduledChatsRefreshTask = nil
        scheduledMessagesRefreshTask?.cancel()
        scheduledMessagesRefreshTask = nil
        resetChatList()
        connectedAccounts = []
        currentUserProfile = nil
        searchResults = nil
        searchQuery = ""
        searchTask?.cancel()
        searchTask = nil
        latestSearchRequestID = nil
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
    }

    // MARK: - Chat list loading

    func loadChats() async {
        guard !APIClient.accessToken.isEmpty else {
            resetChatList()
            return
        }

        let requestedFilter = selectedFilter
        let shouldPreserveExistingChats = lastLoadedFilterID == requestedFilter.id
        let tokenAtStart = APIClient.accessToken

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
                  APIClient.accessToken == tokenAtStart, !Task.isCancelled else { return }
            let refreshedChats = response.items
            let refreshedCursor = response.oldestCursor
            let refreshedHasMoreChats = response.hasMore ?? false
            if !shouldPreserveExistingChats { chatWindowSize = 25 }

            let preservesOlderPages = shouldPreserveExistingChats && chats.count > refreshedChats.count
            setChats(Array(mergedChatsPreservingExistingContext(
                refreshedChats: refreshedChats,
                existingChats: chats,
                shouldPreserveExistingChats: shouldPreserveExistingChats
            ).prefix(chatWindowSize)))
            if !preservesOlderPages {
                chatsCursor = refreshedCursor
                hasMoreChats = refreshedHasMoreChats
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
                  APIClient.accessToken == tokenAtStart, !Task.isCancelled else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return
            }
            chatsError = error.localizedDescription
        }
    }

    func loadMoreChats() async {
        guard !APIClient.accessToken.isEmpty else { return }
        guard hasMoreChats, let cursor = ChatPaginationCursor.encode(chats.last) ?? chatsCursor else { return }
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
            chatWindowSize = max(chatWindowSize + 25, chats.count)
            chatsCursor = response.oldestCursor
            hasMoreChats = response.hasMore ?? false
        } catch {
            // The Load More button remains available to retry.
        }
    }

    // MARK: - Search

    func submitSearch() {
        let trimmed = searchQuery.trimmed
        guard !trimmed.isEmpty else {
            resetSearch()
            return
        }

        searchTask?.cancel()
        let requestID = UUID()
        latestSearchRequestID = requestID
        searchResults = []
        isSearching = true

        let requestedFilter = selectedFilter
        searchTask = Task { [weak self] in
            await self?.performSearch(
                query: trimmed,
                filter: requestedFilter,
                requestID: requestID
            )
        }
    }

    private func performSearch(
        query: String,
        filter: ChatFilter,
        requestID: UUID
    ) async {
        let inboxFilter: InboxFilter = switch filter {
        case .inbox(let inbox): inbox
        case .service: .primary
        }

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
                inbox: inboxFilter.rawValue,
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

    private func resetSearch() {
        searchTask?.cancel()
        searchTask = nil
        latestSearchRequestID = nil
        searchResults = nil
        isSearching = false
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
            return
        }
        do { try await notificationService.syncNotificationPreferences() }
        catch { chatsError = "Archive setting saved, but notification preferences could not be updated. Reopen Relay to retry." }
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
            return
        }
        do { try await notificationService.syncNotificationPreferences() }
        catch { chatsError = "Mute setting saved, but the notification filter could not be updated. Reopen Relay to retry." }
    }

    func markChatAsRead(_ chatID: String) async {
        guard !APIClient.accessToken.isEmpty else { return }

        notificationService.clearDeliveredNotifications(for: chatID)
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

            // Database reads may equal state already applied from local events.
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
            if olderMessagesCursor == nil {
                olderMessagesCursor = response.oldestCursor
                hasMoreOlderMessages = response.hasMore
            }
            applyPreview(response.preview, chatID: chatID)
        } catch {
            guard latestLoadRequestID == requestID else { return }
            handleMessageError(error)
        }
    }

    /// Whether the local database has supplied this chat's initial page.
    func hasLoadedTimeline(for chatID: String) -> Bool {
        messagesChatID == chatID
    }

    /// Wait for the store-owned database read before positioning the timeline.
    func awaitInitialMessages(for chatID: String) async {
        guard !hasLoadedTimeline(for: chatID) else { return }
        await loadMessagesTask?.value
    }

    @discardableResult
    func loadOlderMessages(for chatID: String) async -> Bool {
        guard !APIClient.accessToken.isEmpty else { return false }
        guard chatID == messagesChatID, hasMoreOlderMessages, !isLoadingOlderMessages else { return false }
        guard var cursor = olderMessagesCursor else { return false }

        let token = APIClient.accessToken
        let generation = timelineGeneration
        isLoadingOlderMessages = true
        defer { if timelineGeneration == generation { isLoadingOlderMessages = false } }

        do {
            repeat {
                let response = try await APIClient.listMessages(
                    chatID: chatID,
                    cursor: cursor,
                    direction: "before"
                )
                guard !Task.isCancelled, chatID == messagesChatID,
                      timelineGeneration == generation, APIClient.accessToken == token else { return false }

                let merged = mergedMessages(existing: messages, incoming: normalizedMessages(response.items))
                let changed = merged != messages
                if changed { messages = merged }
                hasMoreOlderMessages = response.hasMore && response.oldestCursor != cursor
                olderMessagesCursor = response.oldestCursor
                applyPreview(response.preview, chatID: chatID)
                if changed { return true }
                // A local page can contain only hidden events. Continue until a
                // visible row or the database boundary, without a retry button.
                guard hasMoreOlderMessages, let next = response.oldestCursor else { return false }
                cursor = next
            } while true
        } catch {
            guard !Task.isCancelled, timelineGeneration == generation,
                  APIClient.accessToken == token else { return false }
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

    private func applyPreview(_ preview: Message?, chatID: String) {
        guard let preview else { return }
        updateChat(chatID) { chat in
            if chat.preview == nil || preview.numericSortKey >= (chat.preview?.numericSortKey ?? .min) {
                chat.preview = preview
            }
        }
    }

    private func updateMessageSubscriptions() {
        var ids = Set(outgoingMessagesByChatID.filter { !$0.value.isEmpty }.keys)
        if let selectedChatID { ids.insert(selectedChatID) }
        realtimeService.setMessageChats(ids)
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
    /// before any upload or Matrix request begins.
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
        return try await AttachmentUploader.upload(
            attachment,
            onPrepared: { prepared in
                self.recordUploadMetadata(prepared, originalAttachmentID: attachment.id, messageID: outgoingMessageID)
            },
            onProgress: { [weak self] progress in
                self?.updateUploadProgress(progress, attachmentID: attachment.id, messageID: outgoingMessageID)
            }
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
            notificationService.notificationPreferencesChanged()
            guard requiresResync else { return }
            scheduleChatsRefresh()
            if let chatID = selectedChatID {
                scheduleMessagesRefresh(chatID: chatID)
            }
        }
    }

    nonisolated func realtimeDidUpdateNotificationPreferences() {
        Task { @MainActor in notificationService.notificationPreferencesChanged() }
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

            // Hydrated events are authoritative. Edits and reactions target
            // the original message ID, so the normal merge updates in place.
            // Background chats read their timeline from the database on open.
            if chatID == selectedChatID {
                applyIncomingMessages(incoming, chatID: chatID)
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
    /// list reload. The summary includes filter membership and ordering.
    private func applyChatUpsert(_ incoming: Chat) {
        if pendingNotificationChatID == incoming.id {
            let filter = ChatFilter.inbox(incoming.isArchived == true ? .archive : .primary)
            if selectedFilter != filter { selectedFilter = filter }
            chatWindowSize = max(chatWindowSize, chats.count + 1)
        }
        updateSelectedChat(incoming)
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
        updated.sort {
            let left = $0.lastActivity ?? .distantPast, right = $1.lastActivity ?? .distantPast
            return left == right ? $0.id < $1.id : left > right
        }
        if updated.count > chatWindowSize { hasMoreChats = true }
        setChats(Array(updated.prefix(chatWindowSize)))
    }

    /// Mirrors server inbox and exact account filtering for hydrated events.
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

    // MARK: - Private storage helpers

    private func setChats(_ newChats: [Chat]) {
        if let selected = newChats.first(where: { $0.id == selectedChatID }) {
            updateSelectedChat(selected)
        }
        // Skip identical commits: Observation invalidates on any write, even when
        // a database reload is equal to the event-applied sidebar state.
        guard newChats != chats else { return }
        chats = newChats
        chatsByID = Dictionary(newChats.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        resolveNotificationChat()
    }

    private func updateSelectedChat(_ incoming: Chat) {
        guard incoming.id == selectedChatID else { return }
        let merged = selectedChatSnapshot?.merging(detail: incoming) ?? incoming
        if merged != selectedChatSnapshot { selectedChatSnapshot = merged }
    }

    private func updateChat(_ chatID: String, _ mutate: (inout Chat) -> Void) {
        if var selected = selectedChatSnapshot, selected.id == chatID {
            mutate(&selected)
            if selected != selectedChatSnapshot { selectedChatSnapshot = selected }
        }
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

    private func resetChatList() {
        setChats([])
        selectedChatID = nil
        chatsCursor = nil
        hasMoreChats = false
        lastLoadedFilterID = nil
        chatWindowSize = 25
        chatsError = nil
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
