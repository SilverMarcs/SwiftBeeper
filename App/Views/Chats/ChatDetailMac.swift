#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct ChatDetailMac: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var inputManager
    @State private var showingChatInfo = false
    @State private var isPreparingInitialScroll = true
    @State private var isNearTop = false
    @State private var firstUnreadID: String?
    @State private var profileSheetParticipant: ChatParticipant?
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
    private let bottomAnchorID = "bottom-id"

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
                List {
                    if chatStore.isLoadingOlderMessages {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
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
                        .id(entry.message.id)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button("Reply", systemImage: "arrowshape.turn.up.left") {
                                withAnimation {
                                    chatStore.setReplyTo(entry.message)
                                }
                            }
                            .tint(.accentColor)
                            .labelStyle(.iconOnly)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !entry.message.isDeletedMessage && entry.message.isOutgoing(in: selectedChat) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    Task {
                                        await chatStore.deleteMessage(entry.message.id, in: selectedChat.id)
                                    }
                                }
                                .labelStyle(.iconOnly)
                            }

                            if chatStore.canEdit(entry.message, in: selectedChat) {
                                Button("Edit", systemImage: "pencil") {
                                    withAnimation {
                                        chatStore.startEditing(entry.message, in: selectedChat)
                                    }
                                }
                                .tint(.orange)
                                .labelStyle(.iconOnly)
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2  , trailing: 10))
                    }

                    ForEach(outgoingTimelineEntries) { entry in
                        if entry.showsTimestamp {
                            TimestampDividerView(timestamp: entry.message.createdAt)
                                .modifier(TimelineFocusEffect(isFocused: activeComposerMessageID == nil))
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 6, trailing: 10))
                        }

                        OutgoingMessageRowView(
                            message: entry.message,
                            linkedMessage: entry.linkedMessage,
                            onTapLinkedMessage: { linkedID in
                                scrollToLinkedMessage(linkedID, chatID: selectedChat.id, proxy: proxy)
                            }
                        )
                        .id(entry.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                    }

                    Color.clear
                        .modifier(TimelineFocusEffect(isFocused: activeComposerMessageID == nil))
                        .listRowInsets(.init())
                        .id(bottomAnchorID)
                }
                .defaultScrollAnchor(.bottom)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top < 80
                } action: { _, nearTop in
                    isNearTop = nearTop
                    guard nearTop, !isPreparingInitialScroll,
                          !messages.isEmpty else { return }
                    loadOlderMessages(chatID: selectedChat.id, proxy: proxy)
                }
                .onChange(of: isPreparingInitialScroll) { _, preparing in
                    if !preparing && isNearTop {
                        loadOlderMessages(chatID: selectedChat.id, proxy: proxy)
                    }
                }
                .task(id: selectedChat.id) {
                    // Re-fires on every selection change (no .id() on the detail
                    // view needed — that would rebuild the whole pane per chat).
                    let chatID = selectedChat.id
                    isPreparingInitialScroll = true
                    firstUnreadID = nil
                    chatStore.setReplyTo(nil)
                    chatStore.cancelEditing()
                    // 2026-07-08: defer bail-out ported from ChatDetailiOS (its
                    // 2026-06-14 scar): the old `guard !Task.isCancelled` before the
                    // clear leaked the mask `true` when a chat switch cancelled this
                    // task mid-sleep — and on macOS this view instance is shared
                    // across chats, so the leak also swallowed message-arrival
                    // scrolls. The settling task owns the happy-path unmask.
                    var settlingOwnsUnmask = false
                    defer {
                        if !settlingOwnsUnmask, chatStore.selectedChat?.id == chatID {
                            isPreparingInitialScroll = false
                        }
                    }
                    // The load itself is owned by the store (survives view churn);
                    // here we just wait for it to settle before sequencing scroll.
                    await chatStore.awaitInitialMessages(for: chatID)
                    firstUnreadID = firstUnreadMessageID(messages: chatStore.messages(for: chatID), chat: selectedChat)
                    try? await Task.sleep(for: .milliseconds(50))
                    scrollToBottomSettling(with: proxy, chatID: chatID)
                    settlingOwnsUnmask = true
                }
                .onChange(of: MessageListTracker(
                    count: messages.count + outgoingMessages.count,
                    lastID: outgoingMessages.last?.timelineKey ?? messages.last?.id
                )) { oldTracker, newTracker in
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

                    let confirmedOptimisticMessage = oldTracker.lastID?.hasPrefix("outgoing-") == true
                        && newTracker.count == oldTracker.count
                    if confirmedOptimisticMessage {
                        // The outgoing and canonical rows have different List
                        // identities. Re-pin after List commits that replacement;
                        // otherwise AppKit preserves the obsolete row's offset and
                        // leaves a small scrollable gap below the new row.
                        Task { @MainActor in
                            await Task.yield()
                            scrollToBottom(with: proxy, animated: false)
                        }
                        return
                    }

                    firstUnreadID = nil
                    Task { @MainActor in
                        // 2026-06-21: scroll exactly once on a new message. The
                        // non-animated re-pin that used to follow at +450ms landed
                        // as a visible abrupt second jump (the "split" scroll).
                        // Row heights are known by layout time (text + pre-sized
                        // media) and re-grouping is synchronous, and the sidebar
                        // refresh now skips no-op commits (it no longer re-measures
                        // the timeline), so the single animated scroll lands clean.
                        try? await Task.sleep(for: .milliseconds(50))
                        scrollToBottom(with: proxy, animated: true)
                    }
                }
                .onChange(of: activeComposerMessageID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .listStyle(.plain)
                .animation(.default, value: activeComposerMessageID)
                .navigationTitle(selectedChat.displayTitle)
                .navigationSubtitle(navigationSubtitle(for: selectedChat))
                .modifier(NavigationBarFocusVisibilityModifier(isFocusedOnComposerMessage: activeComposerMessageID != nil))
                .toolbar {
                    ToolbarItem(placement: .navigation) {
                        if selectedChat.isSingleChat, let other = selectedChat.otherParticipant {
                            Button {
                                profileSheetParticipant = other
                            } label: {
                                ChatAvatarView(chat: selectedChat, dimension: 28)
                            }
                            .buttonStyle(.plain)
                        } else {
                            ChatAvatarView(chat: selectedChat, dimension: 28)
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)

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
                    if isPreparingInitialScroll,
                       !chatStore.hasLoadedTimeline(for: selectedChat.id) {
                        ZStack {
                            Rectangle()
                                .fill(.background)
                            ProgressView()
                                .controlSize(.large)
                        }
                        .ignoresSafeArea(edges: .vertical)
                    }
                }
                .onDrop(of: [.item], isTargeted: nil) { providers in
                    inputManager.handleDrop(providers)
                }
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    MessageInputView()
                }
            }
        } else {
            ContentUnavailableView(
                "Pick a Chat",
                systemImage: "list.bullet",
                description: Text("Select a chat from the sidebar to view messages.")
            )
            .task {
                chatStore.selectedChatID = nil
                isPreparingInitialScroll = false
            }
        }
    }

    private func scrollToBottom(with proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }

    /// Initial-open only: pins to the bottom, re-pins across a short window, and
    /// drops the mask after the final pin. Message-arrival scrolls stay a single
    /// animated scroll (see the 2026-06-21 note in the tracker onChange).
    ///
    /// 2026-07-08: ported from ChatDetailiOS. The single scrollTo landed against
    /// NSTableView's estimated row heights, so chats with late-measuring rows
    /// (media, link pills) settled slightly above the bottom after the mask was
    /// already down. Unlike iOS this view instance is shared across chats (no
    /// .id() per chat), so a stale run from a fast chat switch must bail on the
    /// identity check instead of clobbering the next chat's mask.
    private func scrollToBottomSettling(with proxy: ScrollViewProxy, chatID: String) {
        Task { @MainActor in
            scrollToBottom(with: proxy, animated: false)
            for step: Duration in [.milliseconds(25), .milliseconds(60), .milliseconds(100)] {
                try? await Task.sleep(for: step)
                guard chatStore.selectedChat?.id == chatID else { return }
                scrollToBottom(with: proxy, animated: false)
            }
            guard chatStore.selectedChat?.id == chatID else { return }
            isPreparingInitialScroll = false
        }
    }

    private func scrollToLinkedMessage(_ linkedID: String, chatID: String, proxy: ScrollViewProxy) {
        let messages = chatStore.messages(for: chatID)
        guard let target = messages.first(where: { $0.id == linkedID }) else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(target.timelineKey, anchor: .center)
        }
    }

    private func loadOlderMessages(chatID: String, proxy: ScrollViewProxy) {
        guard chatStore.selectedChatID == chatID, chatStore.hasMoreMessages(for: chatID),
              !chatStore.isLoadingOlderMessages else { return }
        let anchorMessageID = chatStore.messages(for: chatID).first?.timelineKey
        Task { @MainActor in
            _ = await chatStore.loadOlderMessages(for: chatID)
            if let anchorMessageID {
                try? await Task.sleep(for: .milliseconds(1))
                guard !Task.isCancelled, chatStore.selectedChatID == chatID else { return }
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
#endif
