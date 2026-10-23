import Foundation
import Observation

/// Observable UI state for the chat list, open timeline, and composer. The
/// Matrix database owns persistence; local events update the displayed values.
/// Reconnects and missed events reload the relevant pages from that database.
@MainActor
@Observable
final class ChatStore {
    private let realtimeService: RealtimeService
    private let notificationService: NotificationService

    private(set) var isSignedIn = false
    /// Replaced on sign-in and sign-out so results from the previous session are dropped.
    @ObservationIgnored private var session = UUID()

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
    private var chatWindowSize = 25
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
        guard notificationService.isAppActive,
              let id = pendingNotificationChatID, chat(byID: id) != nil else { return }
        pendingNotificationChatID = nil
        selectedChatID = id
        notificationSelectionID = UUID()
    }

    private func loadPendingNotificationChat() {
        guard notificationService.isAppActive, isSignedIn,
              let id = pendingNotificationChatID,
              !isLoadingChats, notificationChatTask == nil else { return }
        let session = session
        let requestID = UUID()
        notificationChatRequestID = requestID
        notificationChatTask = Task { [weak self] in
            guard let self else { return }
            defer { if notificationChatRequestID == requestID { notificationChatTask = nil } }
            do {
                let chat = try await APIClient.getChat(chatID: id)
                guard !Task.isCancelled, pendingNotificationChatID == id,
                      self.session == session else { return }
                applyChatUpsert(chat)
            } catch {
                // A room not yet present stays pending for its local sync event.
            }
        }
    }

    /// The open chat. A snapshot, so a chat outside the loaded sidebar
    /// (a search result or a notification tap) stays open.
    private(set) var selectedChat: Chat?

    var selectedChatID: String? {
        didSet {
            guard oldValue != selectedChatID else { return }
            selectedChat = selectedChatID.flatMap { chat(byID: $0) }
            resetTimeline()
            updateMessageSubscriptions()

            // The store owns the database read so view recreation cannot cancel it.
            if let chatID = selectedChatID {
                notificationService.clearDeliveredNotifications(for: chatID)
                loadMessagesTask = Task { [weak self] in
                    await MatrixRuntime.shared.openedRoom(chatID)
                    guard !Task.isCancelled else { return }
                    await self?.loadMessages()
                }
            } else {
                Task { await MatrixRuntime.shared.openedRoom(nil) }
            }
        }
    }

    // MARK: Open-chat timeline

    /// The open chat's messages, oldest first, without reactions or membership events.
    private(set) var messages: [Message] = []
    /// Whether the open chat's first page has arrived.
    private(set) var hasLoadedTimeline = false
    private(set) var hasMoreOlderMessages = false
    /// Furthest sortKey another participant has read in the open chat.
    private(set) var lastReadByOtherSortKey: String?
    private(set) var isLoadingOlderMessages = false
    private(set) var isLoadingMessages = false
    /// New messages use independent optimistic outbox items; edits still use a
    /// blocking request and temporarily lock the composer.
    private(set) var isSavingEdit = false
    var messagesError: String?
    /// Replaced whenever the open chat changes, so a request for the previous
    /// chat cannot write into the new timeline.
    @ObservationIgnored private var timelineGeneration = UUID()
    @ObservationIgnored private var olderMessagesCursor: String?
    @ObservationIgnored private var loadMessagesTask: Task<Void, Never>?

    // MARK: Composer / outbox

    var replyingToMessage: Message?
    var editingMessage: Message?
    private(set) var outgoingMessagesByChatID: [String: [OutgoingMessage]] = [:] {
        didSet { updateMessageSubscriptions() }
    }
    @ObservationIgnored private var outgoingSendTasks: [OutgoingMessage.ID: Task<Void, Never>] = [:]
    #if os(iOS)
    /// Carries exact outbox identity across the local-to-canonical handoff.
    @ObservationIgnored var onOutgoingMessageConfirmed: ((OutgoingMessage.ID, Message) -> Void)?
    #endif

    var activeComposerMessage: Message? {
        editingMessage ?? replyingToMessage
    }

    @ObservationIgnored private var resyncTask: Task<Void, Never>?

    init(
        realtimeService: RealtimeService,
        notificationService: NotificationService
    ) {
        self.realtimeService = realtimeService
        self.notificationService = notificationService
        realtimeService.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    /// Convenience for view previews.
    convenience init() {
        self.init(realtimeService: RealtimeService(), notificationService: NotificationService())
    }

    // MARK: - Derived accessors

    var displayedChats: [Chat] {
        searchQuery.isBlank ? chats : (searchResults ?? chats)
    }

    /// Which chat to fall back to when the current selection becomes invalid.
    /// macOS and iPad auto-select the first chat; iPhone stays manual (nil).
    private var autoSelectedChatID: String? {
        Device.isIPhone ? nil : chats.first?.id
    }

    func chat(byID chatID: String) -> Chat? {
        if selectedChat?.id == chatID { return selectedChat }
        return chats.first { $0.id == chatID } ?? searchResults?.first { $0.id == chatID }
    }

    /// The open chat's optimistic rows.
    var outgoingMessages: [OutgoingMessage] {
        selectedChatID.flatMap { outgoingMessagesByChatID[$0] } ?? []
    }

    /// The open timeline without server echoes that an outgoing row still shows.
    var timelineMessages: [Message] {
        let shownByOutgoingRows = Set(outgoingMessages.flatMap(\.confirmedMessageIDs))
        guard !shownByOutgoingRows.isEmpty else { return messages }
        return messages.filter { !shownByOutgoingRows.contains($0.id) }
    }

    // MARK: - Lifecycle

    func setSignedIn(_ signedIn: Bool) async {
        guard signedIn != isSignedIn else { return }

        realtimeService.reset()
        isSignedIn = signedIn
        session = UUID()
        clearState()
        guard signedIn else { return }

        let session = session
        await loadChats()
        guard self.session == session else { return }
        realtimeService.start()
        await loadSession()
    }

    private func loadSession() async {
        let session = session
        do {
            let output = try await APIClient.getSession()
            guard self.session == session else { return }
            currentUserProfile = output.user
            connectedAccounts = output.accounts
        } catch {
            // Non-critical; chat and realtime loading remain usable.
        }
    }

    /// Tracks whether Relay is frontmost. iOS also suspends local updates in
    /// the background; they resync when it returns.
    func setAppActive(_ active: Bool) {
        notificationService.setAppActive(active)
        #if os(iOS)
        if !active { realtimeService.stop() }
        #endif
        guard active else { return }
        // Also retries a stream that failed to start; a running one is untouched.
        if isSignedIn { realtimeService.start() }
        resolveNotificationChat()
        loadPendingNotificationChat()
    }

    private func clearState() {
        notificationChatTask?.cancel()
        notificationChatTask = nil
        notificationChatRequestID = UUID()
        if !isSignedIn {
            pendingNotificationChatID = nil
            notificationSelectionID = nil
        }
        resyncTask?.cancel()
        resyncTask = nil
        // Clearing the selection also resets the open timeline.
        resetChatList()
        connectedAccounts = []
        currentUserProfile = nil
        searchQuery = ""
        resetSearch()
        for task in outgoingSendTasks.values {
            task.cancel()
        }
        outgoingSendTasks = [:]
        outgoingMessagesByChatID = [:]
    }

    // MARK: - Chat list loading

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
            if !shouldPreserveExistingChats { chatWindowSize = 25 }

            // A refresh of the same list keeps the older pages already scrolled in.
            var refreshedChats = response.items
            let preservesOlderPages = shouldPreserveExistingChats && chats.count > refreshedChats.count
            if shouldPreserveExistingChats {
                let refreshedIDs = Set(refreshedChats.map(\.id))
                refreshedChats += chats.filter { !refreshedIDs.contains($0.id) }
            }
            setChats(Array(refreshedChats.prefix(chatWindowSize)))
            if !preservesOlderPages {
                chatsCursor = response.oldestCursor
                hasMoreChats = response.hasMore ?? false
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
        guard hasMoreChats, let cursor = ChatPaginationCursor.encode(chats.last) ?? chatsCursor else { return }

        let requestedFilter = selectedFilter
        let requestID = latestChatsRequestID
        let session = session

        isLoadingMoreChats = true
        defer { isLoadingMoreChats = false }

        do {
            let response = try await APIClient.listChats(
                inbox: selectedInboxFilter.rawValue,
                accountIDs: requestedFilter.accountIDs,
                cursor: cursor,
                direction: "before"
            )
            guard selectedFilter.id == requestedFilter.id,
                  latestChatsRequestID == requestID, !isLoadingChats,
                  self.session == session,
                  searchQuery.isBlank, !Task.isCancelled else { return }
            let existingIDs = Set(chats.map(\.id))
            let newChats = response.items.filter { !existingIDs.contains($0.id) }
            setChats(chats + newChats)
            chatWindowSize = max(chatWindowSize + 25, chats.count)
            chatsCursor = response.oldestCursor
            hasMoreChats = (response.hasMore ?? false) && response.oldestCursor != cursor
        } catch {
            // Scrolling down again retries the same local page.
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

    // MARK: - Message loading (open chat only)

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
                let response = try await APIClient.listMessages(
                    chatID: chatID,
                    cursor: cursor,
                    direction: "before"
                )
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
    private func upsertMessages(_ incoming: [Message]) {
        var byID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for message in incoming where message.isDisplayable {
            byID[message.id] = message
        }
        let updated = byID.values.sorted { ($0.numericSortKey, $0.id) < ($1.numericSortKey, $1.id) }
        // Database reloads often equal the event-applied state; skip the no-op write.
        if updated != messages { messages = updated }
    }

    /// Only the open chat keeps a timeline in memory.
    private func resetTimeline() {
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

    private func updateMessageSubscriptions() {
        var ids = Set(outgoingMessagesByChatID.filter { !$0.value.isEmpty }.keys)
        if let selectedChatID { ids.insert(selectedChatID) }
        realtimeService.setMessageChats(ids)
    }

    /// Assigns each canonical message to at most one optimistic row. Transaction
    /// IDs are preferred; content matching covers an event that lands before
    /// the send call returns its transaction ID.
    private func reconcileOutgoingMessages(with incoming: [Message], chatID: String) {
        guard var outgoing = outgoingMessagesByChatID[chatID], !outgoing.isEmpty else { return }

        for message in incoming where message.isSender {
            guard let index = outgoing.firstIndex(where: {
                !$0.confirmedMessageIDs.contains(message.id) && $0.matchesConfirmedMessage(message)
            }) else { continue }

            outgoing[index].confirmedMessageIDs.insert(message.id)
            #if os(iOS)
            onOutgoingMessageConfirmed?(outgoing[index].id, message)
            #endif
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
    func sendMessage(text: String, attachments: [PendingAttachment], to chatID: String) -> OutgoingMessage? {
        let trimmedText = text.trimmed
        let hasText = !trimmedText.isEmpty
        guard hasText || !attachments.isEmpty else { return nil }

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
        return outgoing
    }

    func retrySending(_ messageID: OutgoingMessage.ID) {
        guard let outgoing = outgoingMessage(withID: messageID),
              case .failed = outgoing.state else { return }

        updateOutgoingMessage(messageID) { message in
            message.state = .sending
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
        return try await AttachmentUploader.upload(attachment) { prepared in
            self.recordUploadMetadata(prepared, originalAttachmentID: attachment.id, messageID: outgoingMessageID)
        }
    }

    private func outgoingMessage(withID messageID: OutgoingMessage.ID) -> OutgoingMessage? {
        outgoingMessagesByChatID.values.lazy.flatMap { $0 }.first { $0.id == messageID }
    }

    private func updateOutgoingMessage(
        _ messageID: OutgoingMessage.ID,
        update: (inout OutgoingMessage) -> Void
    ) {
        guard let chatID = outgoingMessage(withID: messageID)?.chatID,
              var messages = outgoingMessagesByChatID[chatID],
              let index = messages.firstIndex(where: { $0.id == messageID }) else { return }

        update(&messages[index])
        outgoingMessagesByChatID[chatID] = messages
    }

    private func recordPendingMessageID(_ pendingMessageID: String, for messageID: OutgoingMessage.ID) {
        guard !pendingMessageID.isEmpty, let chatID = outgoingMessage(withID: messageID)?.chatID else { return }
        updateOutgoingMessage(messageID) { message in
            message.pendingMessageIDs.insert(pendingMessageID)
        }
        // The echo can land before the send call returns its transaction ID.
        guard chatID == selectedChatID else { return }
        reconcileOutgoingMessages(with: messages.filter { $0.transactionID == pendingMessageID }, chatID: chatID)
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

    func setReplyTo(_ message: Message?) {
        if message != nil { editingMessage = nil }
        replyingToMessage = message
    }

    func canEdit(_ message: Message, in chat: Chat) -> Bool {
        guard !message.isDeletedMessage, message.isSender else { return false }
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

    func cancelComposerAction() {
        replyingToMessage = nil
        editingMessage = nil
    }

    func saveEdit(newText: String) async -> Bool {
        guard let message = editingMessage else { return false }

        let trimmedText = newText.trimmed
        guard !trimmedText.isEmpty else { return false }

        isSavingEdit = true
        defer { isSavingEdit = false }

        do {
            try await APIClient.editMessage(chatID: message.chatID, messageID: message.id, text: trimmedText)
            editingMessage = nil
            messagesError = nil
            return true
        } catch {
            handleMessageError(error)
            return false
        }
    }

    func addReaction(to messageID: String, in chatID: String, reactionKey: String) async {
        do {
            try await APIClient.addReaction(chatID: chatID, messageID: messageID, reactionKey: reactionKey)
        } catch {
            handleMessageError(error)
        }
    }

    func removeReaction(from messageID: String, in chatID: String, reactionKey: String) async {
        do {
            try await APIClient.removeReaction(chatID: chatID, messageID: messageID, reactionKey: reactionKey)
        } catch {
            handleMessageError(error)
        }
    }

    func deleteMessage(_ messageID: String, in chatID: String) async {
        do {
            try await APIClient.deleteMessage(chatID: chatID, messageID: messageID)
        } catch {
            handleMessageError(error)
        }
    }

    // MARK: - Realtime events

    private func handle(_ event: RealtimeEvent) {
        switch event {
        case .connected(let requiresResync):
            notificationService.notificationPreferencesChanged()
            if requiresResync { scheduleResync() }
        case .resyncRequired:
            scheduleResync()
        case .notificationPreferencesChanged:
            notificationService.notificationPreferencesChanged()
        case .chatUpserted(let chat):
            applyChatUpsert(chat)
        case .chatDeleted(let chatID):
            removeChatLocally(chatID)
        case .messagesUpserted(let chatID, let incoming):
            // Reconcile first so a confirmed send never renders twice.
            reconcileOutgoingMessages(with: incoming, chatID: chatID)
            // Background chats read their timeline from the database on open.
            if chatID == selectedChatID { upsertMessages(incoming) }
        case .receiptUpdated(let chatID, let readKey):
            if chatID == selectedChatID { lastReadByOtherSortKey = readKey }
        case .failed(let message):
            messagesError = message
        }
    }

    /// Reloads the chat list and open timeline after a short pause that
    /// coalesces bursts of missed events.
    private func scheduleResync() {
        resyncTask?.cancel()
        resyncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard let self, !Task.isCancelled else { return }
            await loadChats()
            await loadMessages()
        }
    }

    /// Applies a `chat.upserted` summary to the sidebar without a full list
    /// reload. The summary includes filter membership and ordering.
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

    // MARK: - Private storage helpers

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

    private func resetChatList() {
        setChats([])
        selectedChatID = nil
        chatsCursor = nil
        hasMoreChats = false
        lastLoadedFilterID = nil
        chatWindowSize = 25
        chatsError = nil
    }

    // MARK: - Errors

    private func handleMessageError(_ error: any Error) {
        if isCancellationLikeError(error) { return }
        messagesError = error.localizedDescription
    }

    private func isCancellationLikeError(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if (error as? URLError)?.code == .cancelled { return true }
        return error.localizedDescription.localizedStandardContains("cancelled")
            || error.localizedDescription.localizedStandardContains("canceled")
    }
}
