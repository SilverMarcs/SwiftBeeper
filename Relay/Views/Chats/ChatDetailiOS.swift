#if !os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct ChatDetailiOS: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var inputManager
    @State private var showingChatInfo = false
    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool
    @State private var delegateProxy: AnyObject?
    @State private var isPreparingInitialScroll = false
    @State private var firstUnreadID: String?
    @State private var profileSheetParticipant: ChatParticipant?
    // Pagination is gated for the first few seconds after the view appears or
    // the chat changes, so the initial bottom-pinned layout doesn't trigger
    // an accidental "load older" while things settle. Loads requested during
    // the gated window are deferred (not dropped) and fire when it opens.
    @State private var paginationGateOpensAt: ContinuousClock.Instant = .now
    @State private var pendingOlderLoad: Task<Void, Never>?
    // Timeline grouping does per-message `Calendar` work; cache it so unrelated
    // store changes (a sidebar refresh) don't recompute it on every body pass.
    @State private var timelineCache = MemoizedValue<TimelineCacheKey, [TimelineEntry]>()
    private let bottomAnchorID = "bottom-id"

    private static let paginationGateDelay: Duration = .seconds(2)

    var body: some View {
        if sessionStore.accessToken.isEmpty {
            TokenRequiredView(
                title: "No Chat Selected",
                systemImage: "bubble.left.and.bubble.right",
                description: "Add a token in Settings first."
            )
        } else if let selectedChat = chatStore.selectedChat {
            let messages = chatStore.messages(for: selectedChat.id)
            let timelineEntries = timelineCache(TimelineCacheKey(messages: messages, firstUnreadID: firstUnreadID)) {
                self.timelineEntries(for: messages)
            }
            let activeComposerMessageID = chatStore.activeComposerMessage?.id
            let readIndicatorMessageID = lastReadOutgoingMessageID(messages: messages, chat: selectedChat)

            ScrollViewReader { proxy in
                List {
                    if chatStore.hasMoreMessages(for: selectedChat.id) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                            // Per-chat identity so the row (and its appear/disappear
                            // callbacks) resets when the chat changes.
                            .id("older-spinner-\(selectedChat.id)")
                            .onAppear {
                                scheduleOlderLoad(chatID: selectedChat.id, proxy: proxy)
                            }
                            .onDisappear {
                                pendingOlderLoad?.cancel()
                                pendingOlderLoad = nil
                            }
                    }

                    ForEach(timelineEntries) { entry in
                        if entry.message.id == firstUnreadID {
                            UnreadDividerView()
                                .modifier(TimelineFocusEffect(isFocused: activeComposerMessageID == nil))
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                        }

                        if entry.showsTimestamp {
                            TimestampDividerView(timestamp: entry.message.timestamp)
                                .modifier(TimelineFocusEffect(isFocused: activeComposerMessageID == nil))
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 6, trailing: 10))
                        }

                        MessageRowView(
                            message: entry.message,
                            chat: selectedChat,
                            showReadIndicator: entry.message.id == readIndicatorMessageID,
                            isFirstInGroup: entry.isFirstInGroup,
                            isLastInGroup: entry.isLastInGroup,
                            onTapLinkedMessage: { linkedID in
                                scrollToLinkedMessage(linkedID, chatID: selectedChat.id, proxy: proxy)
                            }
                        )
                        .modifier(
                            TimelineFocusEffect(
                                isFocused: activeComposerMessageID == nil || activeComposerMessageID == entry.message.id
                            )
                        )
                        .id(entry.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                    }

                    Color.clear
                        .modifier(TimelineFocusEffect(isFocused: activeComposerMessageID == nil))
                        .frame(height: 20)
                        .listRowSeparator(.hidden)
                        .listRowInsets(.init())
                        .id(bottomAnchorID)
                }
                .scrollDismissesKeyboard(.interactively)
                .environment(\.defaultMinListRowHeight, 1)
                .listStyle(.plain)
                .task(id: selectedChat.id) {
                    // Runs on appear AND when the chat changes (same check for
                    // both): push the pagination gate out by the delay.
                    let chatID = selectedChat.id
                    paginationGateOpensAt = ContinuousClock.now.advanced(by: Self.paginationGateDelay)
                    isPreparingInitialScroll = true
                    firstUnreadID = nil
                    chatStore.setReplyTo(nil)
                    chatStore.cancelEditing()
                    // 2026-06-14: clear the flag in a defer so a cancelled task can't
                    // leak it `true`. The old `guard !Task.isCancelled` before the
                    // clear meant that if this task was cancelled during the trailing
                    // sleep (view churn on a chat switch), the flag stuck `true` and
                    // the tracker below silently swallowed EVERY message-arrival
                    // scroll from the second chat onward. The identity check keeps a
                    // chat switch from clobbering the next chat's freshly-set flag.
                    defer {
                        if chatStore.selectedChat?.id == chatID { isPreparingInitialScroll = false }
                    }
                    async let detail: () = chatStore.loadChatDetail(for: chatID)
                    // The load itself is owned by the store (survives view churn);
                    // here we just wait for it to settle before sequencing scroll.
                    await chatStore.awaitCurrentMessagesLoad()
                    firstUnreadID = firstUnreadMessageID(messages: chatStore.messages(for: chatID), chat: selectedChat)
                    try? await Task.sleep(for: .milliseconds(50))
                    scrollToBottomSettling(with: proxy, animateFirst: false)
                    try? await Task.sleep(for: .milliseconds(100))
                    await detail
                }
                .onChange(of: MessageListTracker(count: messages.count, lastID: messages.last?.id)) { oldTracker, newTracker in
                    guard !isPreparingInitialScroll else { return }
                    // 2026-06-06: a send lands as two store commits — the WS merge
                    // grows the array but the new message isn't last yet (its sort
                    // key settles on the follow-up loadMessages commit), then the
                    // reload swaps lastID with the count unchanged. Requiring
                    // count-grew AND lastID-changed in a single transition matched
                    // neither commit, so sending never scrolled. Trigger on lastID
                    // change with a non-decreasing count: pagination keeps lastID
                    // stable, deletions shrink the count — both still skipped.
                    guard newTracker.lastID != oldTracker.lastID else { return }
                    guard newTracker.count >= oldTracker.count else { return }

                    firstUnreadID = nil
                    scrollToBottomSettling(with: proxy, animateFirst: true)
                }
                .onChange(of: activeComposerMessageID) { _, newValue in
                    guard let newValue,
                          let target = chatStore.messages(for: selectedChat.id).first(where: { $0.id == newValue })
                    else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(target.timelineKey, anchor: .center)
                    }
                }
                .animation(.default, value: activeComposerMessageID)
                .modifier(NavigationBarFocusVisibilityModifier(isFocusedOnComposerMessage: activeComposerMessageID != nil))
                .toolbar {
                    // iPad: avatar + name lives in the leading (navigation) slot.
                    // iPhone: stays centered in the title slot.
                    ToolbarItem(placement: isIPad ? .navigation : .principal) {
                        Button {
                            if selectedChat.isSingleChat, let other = selectedChat.otherParticipant {
                                profileSheetParticipant = other
                            } else {
                                showingChatInfo = true
                            }
                        } label: {
                            HStack {
                                ChatAvatarView(chat: selectedChat, dimension: 28)
                                Text(selectedChat.displayTitle)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: isIPhone ? 180 : nil)
                            }
                        }
                    }
                    // .sharedBackgroundVisibility(.hidden)

                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showingChatInfo = true
                        } label: {
                            Label("Chat Info", systemImage: "info")
                        }
                    }
                }
                .sheet(isPresented: $showingChatInfo) {
                    ChatInfoSheet(chat: selectedChat)
                }
                .sheet(item: $profileSheetParticipant) { participant in
                    ParticipantProfileSheet(participant: participant)
                }
                .overlay {
                    if isIPad {
                    if isPreparingInitialScroll {
                        ZStack {
                            Rectangle()
                                .fill(.background)
                            ProgressView()
                                .controlSize(.large)
                        }
                        .ignoresSafeArea(edges: .vertical)
                    }
                    }
                }
                .onDrop(of: [.item], isTargeted: nil) { providers in
                    inputManager.handleDrop(providers)
                }
                .if(isIPhone) {
                    // iPhone: the navigation search field is the composer.
                    $0.onChange(of: chatStore.editingMessage?.id) { _, _ in
                        inputManager.editingMessageDidChange()
                    }
                    .searchable(text: inputManager.draftBinding, isPresented: $isSearchPresented, prompt: Text(inputManager.messageFieldPrompt))
                        .searchFocused($isSearchFocused)
                        .searchPresentationToolbarBehavior(.avoidHidingContent)
                        .background(
                            SearchIntrospector { textField in
                                if delegateProxy == nil {
                                    let proxy = TextFieldDelegateProxy(originalDelegate: textField.delegate)
                                    proxy.shouldReturn = {
                                        inputManager.handleSubmit()
                                        return false
                                    }
                                    textField.delegate = proxy
                                    delegateProxy = proxy
                                }
                            }
                        )
                        .onSubmit(of: .search) {
                            inputManager.handleSubmit()
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(50))
                                isSearchFocused = true
                            }
                            // 2026-06-05: the sent message lands almost instantly
                            // (in-process backend), so the tracker's scroll fires
                            // mid search-bar dismissal and gets swallowed by the
                            // inset animation. Re-scroll after it settles.
                            scrollToBottom(with: proxy, animated: true, delay: .milliseconds(350))
                        }
                        .onChange(of: isSearchFocused) { _, focused in
                            guard focused else { return }
                            // 2026-06-14: focusing for a reply/edit must NOT jump to
                            // the bottom — that scrolls past the message being acted
                            // on. The activeComposerMessageID handler below reveals
                            // the target instead; only bottom-pin a fresh compose.
                            guard chatStore.activeComposerMessage == nil else { return }
                            // 2026-06-05: scrolling immediately is a no-op — the
                            // keyboard hasn't presented yet, so the bottom is
                            // "visible" and then gets covered as it slides up.
                            // Wait out the keyboard transition before scrolling.
                            scrollToBottom(with: proxy, animated: true, delay: .milliseconds(250))
                        }
                        .onChange(of: inputManager.isSendingMessage) { oldValue, newValue in
                            if oldValue && !newValue {
                                isSearchFocused = true
                            }
                        }
                        .onChange(of: activeComposerMessageID) { _, newValue in
                            // Entering reply/edit state:
                            guard newValue != nil else { return }
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(200))
                                // try? await Task.sleep(for: .milliseconds(450))
                                isSearchFocused = true
                            }
                        }
                        .onChange(of: isSearchPresented) { _, presented in
                            // Exiting the search/compose mode (Cancel) should also
                            // bail out of any reply/edit state — they're entered
                            // together, so leaving one leaves the other. A bare
                            // keyboard dismissal keeps the search presented, so this
                            // only fires on a real search exit.
                            guard !presented, chatStore.activeComposerMessage != nil else { return }
                            inputManager.cancelComposerAction()
                        }
                        .safeAreaInset(edge: .bottom) {
                            MessagePendingAttachmentsBar()
                        }
                        .toolbar {
                            ToolbarItem(placement: .bottomBar) {
                                MessageInputMenu()
                            }
                            ToolbarSpacer(.fixed, placement: .bottomBar)
                            DefaultToolbarItem(kind: .search, placement: .bottomBar)
                            if inputManager.isSendingMessage {
                                ToolbarItem(placement: .bottomBar) {
                                    ProgressView()
                                }
                            }
                        }
                }
                .if(isIPad) {
                    // iPad: same inline composer as macOS.
                    $0.safeAreaBar(edge: .bottom, spacing: 0) {
                        MessageInputView()
                    }
                    // 2026-06-05: the inline composer's FocusState is private to
                    // MessageInputView, so nothing scrolled when the keyboard
                    // came up and it covered the latest messages. The composer
                    // mirrors its focus into InputManager; scroll once the
                    // keyboard transition settles.
                    .onChange(of: inputManager.isComposerFocused) { _, focused in
                        guard focused else { return }
                        scrollToBottom(with: proxy, animated: true, delay: .milliseconds(250))
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Pick a Chat",
                systemImage: "list.bullet",
                description: Text("Select a chat from the sidebar to view messages.")
            )
        }
    }

    /// `delay` waits out keyboard / search-bar transitions: a scrollTo issued
    /// while the List's bottom inset is still animating either targets the
    /// pre-transition layout or is swallowed outright (macOS is unaffected —
    /// no on-screen keyboard).
    private func scrollToBottom(with proxy: ScrollViewProxy, animated: Bool, delay: Duration = .zero) {
        let scroll = {
            if animated {
                withAnimation {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        }

        if delay == .zero {
            scroll()
        } else {
            Task { @MainActor in
                try? await Task.sleep(for: delay)
                scroll()
            }
        }
    }

    /// Scrolls to the bottom, then re-pins several times across a short window.
    ///
    /// 2026-06-14: rows re-measure at unpredictable times *after* the first
    /// scroll — on iPhone the .searchable submit churns the keyboard (down then
    /// up) on every send, and async avatar/media height plus bubble re-grouping
    /// (the previous message's `isLastInGroup` flips, hiding its avatar) shift
    /// layout too. A single fixed-delay re-pin races whichever settle happens to
    /// land last, leaving the list slightly off-bottom. Re-pinning across the
    /// window catches the late ones. iPad/Mac use the inline composer (no
    /// search-bar keyboard churn), which is why they were less affected.
    private func scrollToBottomSettling(with proxy: ScrollViewProxy, animateFirst: Bool) {
        Task { @MainActor in
            scrollToBottom(with: proxy, animated: animateFirst)
            for step: Duration in [.milliseconds(150), .milliseconds(300), .milliseconds(500)] {
                try? await Task.sleep(for: step)
                if Task.isCancelled { return }
                scrollToBottom(with: proxy, animated: false)
            }
        }
    }

    private func scrollToLinkedMessage(_ linkedID: String, chatID: String, proxy: ScrollViewProxy) {
        let messages = chatStore.messages(for: chatID)
        guard let target = messages.first(where: { $0.id == linkedID }) else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(target.timelineKey, anchor: .center)
        }
    }

    /// Defers the "load older" request until the pagination gate opens.
    /// If the gate is already open, the sleep returns immediately and this
    /// behaves like the plain onAppear-triggered load.
    private func scheduleOlderLoad(chatID: String, proxy: ScrollViewProxy) {
        pendingOlderLoad?.cancel()
        let opensAt = paginationGateOpensAt
        pendingOlderLoad = Task { @MainActor in
            try? await Task.sleep(until: opensAt, clock: .continuous)
            guard !Task.isCancelled else { return }
            guard !chatStore.isLoadingOlderMessages else { return }
            loadOlderMessages(chatID: chatID, proxy: proxy)
        }
    }

    private func loadOlderMessages(chatID: String, proxy: ScrollViewProxy) {
        let anchorMessageID = chatStore.messages(for: chatID).first?.timelineKey
        Task { @MainActor in
            _ = await chatStore.loadOlderMessages(for: chatID)
            if let anchorMessageID {
                // Re-anchor so the prepended page doesn't shift what's on screen.
                try? await Task.sleep(for: .milliseconds(1))
                proxy.scrollTo(anchorMessageID, anchor: .top)
            }
        }
    }

    private func firstUnreadMessageID(messages: [Message], chat: Chat) -> String? {
        guard chat.unreadCount > 0 else { return nil }

        if let lastReadSortKey = chat.lastReadMessageSortKey {
            let lastReadNumeric = Int64(lastReadSortKey) ?? 0
            return messages.first(where: { $0.numericSortKey > lastReadNumeric })?.id
        }

        return messages.first(where: { $0.isUnread == true })?.id
    }

    /// Returns the ID of the outgoing message that should show the "Read" indicator.
    /// Rules:
    /// - Only the last outgoing message that the other side has read gets the indicator.
    /// - If there's an incoming message AFTER that outgoing message, don't show
    ///   the indicator — the reply itself proves they read it.
    private func lastReadOutgoingMessageID(messages: [Message], chat: Chat) -> String? {
        // Find the last outgoing message that the other side has read.
        var lastReadOutgoing: Message?
        for message in messages {
            guard message.isOutgoing(in: chat) else { continue }
            guard chatStore.isReadByOther(message: message) else { continue }
            lastReadOutgoing = message
        }
        guard let target = lastReadOutgoing else { return nil }

        // If there's any incoming message after the target, the reply proves
        // reading — no need for an explicit indicator.
        let hasIncomingAfter = messages.contains { msg in
            !msg.isOutgoing(in: chat) && msg.numericSortKey > target.numericSortKey
        }
        if hasIncomingAfter {
            return nil
        }

        return target.id
    }

    private func timelineEntries(for messages: [Message]) -> [TimelineEntry] {
        var entries: [TimelineEntry] = []
        let count = messages.count

        for i in 0..<count {
            let message = messages[i]
            let prev: Message? = i > 0 ? messages[i - 1] : nil
            let next: Message? = i < count - 1 ? messages[i + 1] : nil

            let showsTimestamp = shouldShowTimestamp(before: message, previousMessage: prev)

            let sameSenderAsPrev = prev.map { $0.senderID == message.senderID } ?? false
            let sameSenderAsNext = next.map { $0.senderID == message.senderID } ?? false

            // A timestamp break or unread divider resets the group
            let nextShowsTimestamp = next.map { shouldShowTimestamp(before: $0, previousMessage: message) } ?? false
            let nextIsUnread = next.map { $0.id == firstUnreadID } ?? false

            let isFirstInGroup = !sameSenderAsPrev || showsTimestamp || message.id == firstUnreadID
            let isLastInGroup = !sameSenderAsNext || nextShowsTimestamp || nextIsUnread

            entries.append(TimelineEntry(message: message, showsTimestamp: showsTimestamp, isFirstInGroup: isFirstInGroup, isLastInGroup: isLastInGroup))
        }

        return entries
    }

    private func shouldShowTimestamp(before message: Message, previousMessage: Message?) -> Bool {
        guard let previousMessage else { return true }

        let calendar = Calendar.app
        if calendar.isDate(message.timestamp, inSameDayAs: previousMessage.timestamp) == false {
            return true
        }

        return message.timestamp.timeIntervalSince(previousMessage.timestamp) >= 30 * 60
    }

    private func navigationSubtitle(for chat: Chat) -> Text {
        guard chat.isGroupChat else { return Text("") }

        let participantCount = chat.participants?.total ?? chat.participants?.items.count ?? 0
        guard participantCount > 0 else { return Text("") }

        return Text("^[\(participantCount) member](inflect: true)")
    }
}

private struct MessageListTracker: Equatable {
    let count: Int
    let lastID: String?
}

/// Memoization key for the timeline grouping: it depends only on the message
/// values and the unread divider's position.
private struct TimelineCacheKey: Equatable {
    let messages: [Message]
    let firstUnreadID: String?
}

private struct TimelineEntry: Identifiable {
    let message: Message
    let showsTimestamp: Bool
    let isFirstInGroup: Bool
    let isLastInGroup: Bool

    var id: String { message.timelineKey }
}

private class TextFieldDelegateProxy: NSObject, UITextFieldDelegate {
    weak var originalDelegate: UITextFieldDelegate?
    var shouldReturn: (() -> Bool)?

    init(originalDelegate: UITextFieldDelegate?) {
        self.originalDelegate = originalDelegate
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(textFieldShouldReturn(_:)) {
            return true
        }
        return originalDelegate?.responds(to: aSelector) ?? super.responds(to: aSelector)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return originalDelegate
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let shouldReturn = shouldReturn {
            return shouldReturn()
        }
        return originalDelegate?.textFieldShouldReturn?(textField) ?? true
    }
}

private struct SearchIntrospector: UIViewRepresentable {
    var introspect: (UISearchTextField) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            if let searchField = findSearchTextField(startingFrom: view) {
                introspect(searchField)
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private func findSearchTextField(startingFrom view: UIView) -> UISearchTextField? {
        if let window = view.window, let field = findSearchTextField(in: window) {
            return field
        }
        var responder: UIResponder? = view
        while responder != nil {
            if let viewController = responder as? UIViewController {
                if let field = findSearchTextField(in: viewController.view) {
                    return field
                }
                if let navigationBar = viewController.navigationController?.navigationBar,
                   let field = findSearchTextField(in: navigationBar) {
                    return field
                }
            }
            responder = responder?.next
        }
        return nil
    }

    private func findSearchTextField(in view: UIView) -> UISearchTextField? {
        if let searchField = view as? UISearchTextField {
            return searchField
        }
        for subview in view.subviews {
            if let field = findSearchTextField(in: subview) {
                return field
            }
        }
        return nil
    }
}
#endif
