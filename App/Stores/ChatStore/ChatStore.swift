import Foundation
import Observation

/// Observable UI state for the chat list, open timeline, and composer. The
/// Matrix database owns persistence; local events update the displayed values.
/// Reconnects and missed events reload the relevant pages from that database.
///
/// Stored state and the session lifecycle live here; the extensions beside
/// this file implement the chat list, the open timeline, and sending. Swift's
/// `private` does not cross files, so state those extensions write has an
/// internal setter. Views write only the selection, filter, and query.
@MainActor
@Observable
final class ChatStore {
    /// Matches the core's `list-chats` page size.
    static let chatPageSize = 25

    private let realtimeService: RealtimeService
    let notificationService: NotificationService

    private(set) var isSignedIn = false
    /// Replaced on sign-in and sign-out so results from the previous session are dropped.
    @ObservationIgnored private(set) var session = UUID()

    // MARK: Chat list

    var chats: [Chat] = []
    var pinnedChats: [Chat] = []
    var pinningChatIDs: Set<String> = []
    var mutingChatIDs: Set<String> = []
    var muteError: String?
    var pinError: String?
    var hasMoreChats = false
    var isLoadingMoreChats = false
    var isLoadingChats = false
    var chatsError: String?
    var selectedFilter: ChatFilter = .inbox(.primary) {
        didSet {
            guard oldValue.id != selectedFilter.id else { return }
            resetSearch()
            resetChatList()
        }
    }
    private(set) var connectedAccounts: [Account] = []
    private(set) var currentUserProfile: ChatParticipant?

    var searchQuery = ""
    var searchResults: [Chat]?
    var isSearching = false
    @ObservationIgnored var latestSearchRequestID: UUID?
    @ObservationIgnored var latestChatsRequestID: UUID?
    @ObservationIgnored var lastLoadedFilterID: String?
    /// How many chats the sidebar holds: the first page plus pages scrolled in.
    @ObservationIgnored var chatWindowSize = ChatStore.chatPageSize

    // MARK: Notification taps

    /// The chat whose timeline is on screen, so its banners stay quiet.
    @ObservationIgnored var visibleChatID: String?
    /// A tapped notification's chat, held until it can be selected.
    @ObservationIgnored private(set) var pendingNotificationChatID: String?
    /// Changes whenever an action opens a chat, including one outside the sidebar.
    var chatNavigationID: UUID?
    @ObservationIgnored private var notificationChatTask: Task<Void, Never>?
    @ObservationIgnored private var notificationChatRequestID = UUID()

    // MARK: Open chat

    /// The open chat. A snapshot, so a chat outside the loaded sidebar
    /// (a search result or a notification tap) stays open.
    var selectedChat: Chat?

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

    /// The open chat's messages, oldest first.
    var messages: [Message] = []
    /// Whether the open chat's first page has arrived.
    var hasLoadedTimeline = false
    var hasMoreOlderMessages = false
    /// Furthest sortKey another participant has read in the open chat.
    var lastReadByOtherSortKey: String?
    var typingParticipants: [ChatParticipant] = []
    var typingBubble: TypingBubble?
    /// Preserve the typing row's identity after its real message arrives.
    var typingMessageRowIDs: [Message.ID: String] = [:]
    @ObservationIgnored var typingExpirationTask: Task<Void, Never>?
    var isLoadingOlderMessages = false
    var isLoadingMessages = false
    var resolvingMediaIDs: Set<String> = []
    var failedMediaIDs: Set<String> = []
    var messagesError: String?
    /// Replaced whenever the open chat changes, so a request for the previous
    /// chat cannot write into the new timeline.
    @ObservationIgnored var timelineGeneration = UUID()
    @ObservationIgnored var olderMessagesCursor: String?
    @ObservationIgnored var loadMessagesTask: Task<Void, Never>?

    // MARK: Composer / outbox

    var replyingToMessage: Message?
    var editingMessage: Message?
    /// New messages use independent optimistic outbox items; edits still use a
    /// blocking request and temporarily lock the composer.
    var isSavingEdit = false
    var outgoingMessagesByChatID: [String: [OutgoingMessage]] = [:] {
        didSet { updateMessageSubscriptions() }
    }
    @ObservationIgnored var outgoingSendTasks: [OutgoingMessage.ID: Task<Void, Never>] = [:]
    /// Carries exact outbox identity across the local-to-canonical handoff.
    @ObservationIgnored var onOutgoingMessageConfirmed: ((OutgoingMessage.ID, Message) -> Void)?

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

    func chat(byID chatID: String) -> Chat? {
        if selectedChat?.id == chatID { return selectedChat }
        return chats.first { $0.id == chatID }
            ?? pinnedChats.first { $0.id == chatID }
            ?? searchResults?.first { $0.id == chatID }
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
        if !active { clearTyping() }
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
        mutingChatIDs = []
        muteError = nil
        resolvingMediaIDs = []
        failedMediaIDs = []
        notificationChatTask?.cancel()
        notificationChatTask = nil
        notificationChatRequestID = UUID()
        if !isSignedIn {
            pendingNotificationChatID = nil
            chatNavigationID = nil
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

    /// Subscribes to message events for the open chat and every chat with
    /// outgoing messages still awaiting their echo.
    private func updateMessageSubscriptions() {
        var ids = Set(outgoingMessagesByChatID.filter { !$0.value.isEmpty }.keys)
        if let selectedChatID { ids.insert(selectedChatID) }
        realtimeService.setMessageChats(ids)
    }

    // MARK: - Notification taps

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

    /// Selects the pending chat once the app is active and the chat is known.
    func resolveNotificationChat() {
        guard notificationService.isAppActive,
              let id = pendingNotificationChatID, let chat = chat(byID: id) else { return }
        pendingNotificationChatID = nil
        openChat(chat)
    }

    /// Fetches the pending chat directly, for one outside the loaded sidebar.
    func loadPendingNotificationChat() {
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

    // MARK: - Realtime events

    private func handle(_ event: RealtimeEvent) {
        switch event {
        case .connected(let requiresResync):
            clearTyping()
            notificationService.notificationPreferencesChanged()
            if requiresResync { scheduleResync() }
        case .disconnected:
            clearTyping()
        case .resyncRequired:
            clearTyping()
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
        case .typingUpdated(let chatID, let participants):
            if chatID == selectedChatID { updateTyping(participants) }
        case .failed(let message):
            clearTyping()
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

    // MARK: - Errors

    /// Shows a timeline or composer failure in the composer banner.
    func handleMessageError(_ error: any Error) {
        if isCancellationLikeError(error) { return }
        messagesError = error.localizedDescription
    }

    /// Besides `CancellationError`, a cancelled core operation surfaces as an
    /// error whose message says so.
    func isCancellationLikeError(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        return error.localizedDescription.localizedStandardContains("cancelled")
            || error.localizedDescription.localizedStandardContains("canceled")
    }
}
