import SwiftUI
import UniformTypeIdentifiers

/// Shared message layout and scrolling, with platform-specific navigation and composers.
struct ChatTimelineView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var inputManager
    #if os(iOS)
    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool
    @State private var delegateProxy: AnyObject?
    @State private var keyboardScrollTask: Task<Void, Never>?
    #endif
    @State private var firstUnreadID: String?
    // Timeline grouping does per-message `Calendar` work; cache it so unrelated
    // store changes (a sidebar refresh) don't recompute it on every body pass.
    @State private var timelineCache = MemoizedValue<TimelineCacheKey, [TimelineEntry]>()
    // Same idea for the optimistic tail: its dividers and quoted replies only
    // change when the timeline or the outgoing rows themselves change, not on
    // every upload-progress tick.
    @State private var outgoingTimelineCache = MemoizedValue<OutgoingTimelineKey, [OutgoingTimelineEntry]>()
    // The read indicator scans every message (isOutgoing + isReadByOther); memoize
    // it so an unrelated store change doesn't re-scan the timeline on each body pass.
    @State private var readIndicatorCache = MemoizedValue<ReadIndicatorKey, String?>()
    private let bottomAnchorID = "timeline-bottom"


    var body: some View {
        if sessionStore.accessToken.isEmpty {
            SignInRequiredView()
        } else if let selectedChat = chatStore.selectedChat {
            let messages = chatStore.messages(for: selectedChat.id)
            let outgoingMessages = chatStore.outgoingMessages(for: selectedChat.id)
            let timelineVersion = chatStore.messagesChatID == selectedChat.id ? chatStore.messagesVersion : -1
            let suppressingOutgoingIDs = outgoingMessages.compactMap(\.suppressionID)
            let timelineEntries = timelineCache(TimelineCacheKey(
                version: timelineVersion,
                firstUnreadID: firstUnreadID,
                suppressingOutgoingIDs: suppressingOutgoingIDs
            )) {
                self.timelineEntries(for: messages)
            }
            let outgoingTimelineEntries = outgoingTimelineCache(OutgoingTimelineKey(
                version: timelineVersion,
                suppressingOutgoingIDs: suppressingOutgoingIDs,
                outgoingKeys: outgoingMessages.map(\.timelineKey)
            )) {
                TimelineTimestampRule.outgoingEntries(for: outgoingMessages, following: messages)
            }
            let activeComposerMessageID = chatStore.activeComposerMessage?.id
            let readIndicatorMessageID = readIndicatorCache(
                ReadIndicatorKey(
                    version: timelineVersion,
                    lastReadByOtherSortKey: chatStore.lastReadByOtherSortKey,
                    selfParticipantID: selectedChat.participants?.items.first(where: { $0.isSelf == true })?.id,
                    suppressingOutgoingIDs: suppressingOutgoingIDs
                )
            ) {
                self.lastReadOutgoingMessageID(messages: messages, chat: selectedChat)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        LazyVStack(spacing: 0) {
                            if chatStore.isLoadingOlderMessages {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            }

                            ForEach(timelineEntries) { entry in
                                VStack(spacing: 0) {
                                    if entry.message.id == firstUnreadID && outgoingMessages.isEmpty {
                                        UnreadDividerView()
                                            .modifier(TimelineFocusEffect(isFocused: activeComposerMessageID == nil))
                                            .padding(.vertical, 4)
                                    }

                                    if entry.showsTimestamp {
                                        TimestampDividerView(timestamp: entry.message.timestamp)
                                            .modifier(TimelineFocusEffect(isFocused: activeComposerMessageID == nil))
                                            .padding(.top, 10)
                                            .padding(.bottom, 6)
                                    }

                                    MessageRowView(
                                        message: entry.message,
                                        chat: selectedChat,
                                        showReadIndicator: entry.message.id == readIndicatorMessageID,
                                        isFirstInGroup: entry.isFirstInGroup,
                                        isLastInGroup: entry.isLastInGroup,
                                        linkedMessage: entry.linkedMessage,
                                        onTapLinkedMessage: { linkedID in
                                            scrollToLinkedMessage(linkedID, chatID: selectedChat.id, proxy: proxy)
                                        }
                                    )
                                    .modifier(
                                        TimelineFocusEffect(
                                            isFocused: activeComposerMessageID == nil || activeComposerMessageID == entry.message.id
                                        )
                                    )
                                    .padding(.vertical, 2)
                                }
                                .id(entry.message.timelineKey)
                            }

                            ForEach(outgoingTimelineEntries) { entry in
                                VStack(spacing: 0) {
                                    if entry.showsTimestamp {
                                        TimestampDividerView(timestamp: entry.message.createdAt)
                                            .modifier(TimelineFocusEffect(isFocused: activeComposerMessageID == nil))
                                            .padding(.top, 10)
                                            .padding(.bottom, 6)
                                    }

                                    OutgoingMessageRowView(
                                        message: entry.message,
                                        linkedMessage: entry.linkedMessage,
                                        onTapLinkedMessage: { linkedID in
                                            scrollToLinkedMessage(linkedID, chatID: selectedChat.id, proxy: proxy)
                                        }
                                    )
                                    .padding(.vertical, 2)
                                }
                                .id(entry.id)
                            }
                        }
                        // Keep the scroll target available independently of lazy rows.
                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                            .accessibilityHidden(true)
                    }
                }
                // Recreate only the viewport when a chat opens or its first
                // database page arrives. Its first layout starts at the bottom.
                .id("\(selectedChat.id)-\(chatStore.hasLoadedTimeline(for: selectedChat.id))")
                // Initial layout and short conversations align to the bottom.
                // Content growth must preserve the starting offset so the
                // explicit send scroll can animate to its new destination.
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .alignment)
                // Insets belong to the scroll view. Explicit scrolling targets
                // the end marker rather than a persistent content-edge offset.
                .contentMargins(.horizontal, 10, for: .scrollContent)
                .contentMargins(.bottom, 24, for: .scrollContent)
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                .scrollClipDisabled(!inputManager.sendAnimator.flights.isEmpty)
                .onChange(of: isSearchFocused || inputManager.isComposerFocused) { _, focused in
                    keyboardScrollTask?.cancel()
                    guard focused,
                          chatStore.activeComposerMessage == nil else { return }
                    // Focus changes keep arriving after the viewport is recreated
                    // for another chat. Schedule from that event, not .task(id:).
                    keyboardScrollTask = Task { @MainActor in
                        do {
                            try await Task.sleep(for: .milliseconds(1))
                        } catch {
                            return
                        }
                        guard !Task.isCancelled,
                              chatStore.selectedChatID == selectedChat.id,
                              chatStore.activeComposerMessage == nil else { return }
                        scrollToLatest(with: proxy)
                    }
                }
                .onDisappear {
                    keyboardScrollTask?.cancel()
                }
                #endif
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top < 80
                } action: { _, nearTop in
                    guard nearTop, chatStore.hasLoadedTimeline(for: selectedChat.id),
                          !messages.isEmpty else { return }
                    loadOlderMessages(chatID: selectedChat.id)
                }
                .onChange(of: selectedChat.id, initial: true) { _, _ in
                    firstUnreadID = nil
                }
                .onChange(of: chatStore.hasLoadedTimeline(for: selectedChat.id), initial: true) { _, loaded in
                    guard loaded else { return }
                    firstUnreadID = firstUnreadMessageID(messages: messages, chat: selectedChat)
                }
                .onChange(of: MessageListTracker(
                    count: messages.count + outgoingMessages.count,
                    lastID: outgoingMessages.last?.timelineKey ?? messages.last?.id
                )) { oldTracker, newTracker in
                    guard chatStore.hasLoadedTimeline(for: selectedChat.id), oldTracker.lastID != nil else { return }
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

                    let confirmedOptimisticMessage = oldTracker.lastID?.hasPrefix("outgoing-") == true
                        && newTracker.count == oldTracker.count
                    firstUnreadID = nil
                    // Confirmation replaces the outgoing row, but not the end
                    // marker. Let the existing scroll animation finish.
                    guard !confirmedOptimisticMessage else { return }
                    scrollToLatest(with: proxy)
                }
                .onChange(of: activeComposerMessageID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(messages.first(where: { $0.id == newValue })?.timelineKey ?? newValue, anchor: .center)
                    }
                }
                .animation(.default, value: activeComposerMessageID)
                .overlay {
                    if !chatStore.hasLoadedTimeline(for: selectedChat.id),
                       let error = chatStore.messagesError, !chatStore.isLoadingMessages {
                        ContentUnavailableView {
                            Label("Couldn’t Load Messages", systemImage: "exclamationmark.bubble")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("Try Again") {
                                Task { await chatStore.loadMessages(for: selectedChat.id) }
                            }
                        }
                    }
                }
                .onDrop(of: [.item], isTargeted: nil) { providers in
                    inputManager.handleDrop(providers)
                }
                #if os(iOS)
                .if(isIPhone) {
                    // iPhone: the navigation search field is the composer.
                    $0.onChange(of: chatStore.editingMessage?.id) { _, _ in
                        inputManager.editingMessageDidChange()
                    }
                    .searchable(text: inputManager.draftBinding, isPresented: $isSearchPresented, prompt: Text(inputManager.messageFieldPrompt))
                        .searchFocused($isSearchFocused)
                        .searchPresentationToolbarBehavior(.avoidHidingContent)
                        .background(
                            SearchIntrospector { textField, referenceView in
                                if textField.returnKeyType != .send {
                                    textField.returnKeyType = .send
                                    if textField.isFirstResponder {
                                        textField.reloadInputViews()
                                    }
                                }
                                let animator = inputManager.sendAnimator
                                animator.sourceFrame = { [weak animator, weak textField, weak referenceView] in
                                    guard let animator, let textField, let referenceView,
                                          textField.window != nil, !textField.isHidden else { return nil }
                                    let frame = textField.convert(textField.bounds, to: referenceView)
                                    let reference = animator.searchReferenceFrame
                                    return frame.offsetBy(dx: reference.minX, dy: reference.minY)
                                }
                                if delegateProxy == nil || textField.delegate !== delegateProxy {
                                    let proxy = TextFieldDelegateProxy(originalDelegate: textField.delegate)
                                    textField.delegate = proxy
                                    delegateProxy = proxy
                                }
                                // Use the field that received Return, even if
                                // SwiftUI has replaced the searchable field.
                                (delegateProxy as? TextFieldDelegateProxy)?.shouldReturn = { [weak referenceView] field in
                                    let sourceFrame = referenceView.map {
                                        field.convert(field.bounds, to: $0).offsetBy(
                                            dx: animator.searchReferenceFrame.minX,
                                            dy: animator.searchReferenceFrame.minY
                                        )
                                    }
                                    inputManager.handleSubmit(sourceFrame: sourceFrame)
                                    return false
                                }
                            }
                            .onGeometryChange(for: CGRect.self) { geometry in
                                geometry.frame(in: .global)
                            } action: { frame in
                                inputManager.sendAnimator.searchReferenceFrame = frame
                            }
                        )
                        .onSubmit(of: .search) {
                            inputManager.handleSubmit()
                            isSearchFocused = true
                        }
                        .onChange(of: inputManager.isSavingEdit) { oldValue, newValue in
                            if oldValue && !newValue {
                                isSearchFocused = true
                            }
                        }
                        .onChange(of: activeComposerMessageID) { _, newValue in
                            // Entering reply/edit state:
                            guard newValue != nil else { return }
                            isSearchFocused = true
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
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            MessagePendingAttachmentsBar()
                        }
                        .toolbar {
                            ToolbarItem(placement: .bottomBar) {
                                MessageInputMenu()
                            }
                            ToolbarSpacer(.fixed, placement: .bottomBar)
                            DefaultToolbarItem(kind: .search, placement: .bottomBar)
                        }
                }
                #endif
                .if(isMacOrPad) {
                    // macOS and iPad share the inline composer.
                    $0.safeAreaBar(edge: .bottom, spacing: 0) {
                        MessageInputView()
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Pick a Chat",
                systemImage: "list.bullet",
                description: Text("Select a chat from the sidebar to view messages.")
            )
            #if os(macOS)
            .task {
                chatStore.selectedChatID = nil
            }
            #endif
        }
    }

    private func scrollToLatest(with proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }

    private func scrollToLinkedMessage(_ linkedID: String, chatID: String, proxy: ScrollViewProxy) {
        guard let target = chatStore.messages(for: chatID).first(where: { $0.id == linkedID }) else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(target.timelineKey, anchor: .center)
        }
    }

    private func loadOlderMessages(chatID: String) {
        guard chatStore.selectedChatID == chatID, chatStore.hasMoreMessages(for: chatID),
              !chatStore.isLoadingOlderMessages else { return }
        Task { @MainActor in
            // Stable scroll targets preserve visible messages when history prepends.
            await chatStore.loadOlderMessages(for: chatID)
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
        // Resolve reply targets once here (the whole result is memoized) so each
        // reply bubble gets its quoted message as plain data instead of
        // subscribing to the store and re-scanning `messages` on every render.
        let messagesByID = Dictionary(messages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

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

            let linkedMessage = message.linkedMessageID.flatMap { $0.isEmpty ? nil : messagesByID[$0] }

            entries.append(TimelineEntry(message: message, showsTimestamp: showsTimestamp, isFirstInGroup: isFirstInGroup, isLastInGroup: isLastInGroup, linkedMessage: linkedMessage))
        }

        return entries
    }

    private func shouldShowTimestamp(before message: Message, previousMessage: Message?) -> Bool {
        TimelineTimestampRule.showsDivider(before: message.timestamp, previous: previousMessage?.timestamp)
    }
}

private struct MessageListTracker: Equatable {
    let count: Int
    let lastID: String?
}

/// Memoization key for the timeline grouping: it depends only on the timeline's
/// content (tracked by the store's O(1) version counter) and the unread divider's
/// position. `version` is -1 when no timeline is shown for the open chat yet.
private struct TimelineCacheKey: Equatable {
    let version: Int
    let firstUnreadID: String?
    let suppressingOutgoingIDs: [OutgoingMessage.ID]
}

/// Memoization key for the "Read" indicator: it depends on the timeline content,
/// how far the other side has read, and who "self" is (which drives `isOutgoing`).
private struct ReadIndicatorKey: Equatable {
    let version: Int
    let lastReadByOtherSortKey: String?
    let selfParticipantID: String?
    let suppressingOutgoingIDs: [OutgoingMessage.ID]
}

private struct TimelineEntry: Identifiable {
    let message: Message
    let showsTimestamp: Bool
    let isFirstInGroup: Bool
    let isLastInGroup: Bool
    let linkedMessage: Message?

    var id: String { message.timelineKey }
}

