#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct ChatDetailMac: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var inputManager
    @State private var showingChatInfo = false
    @State private var isPreparingInitialScroll = false
    @State private var firstUnreadID: String?
    @State private var profileSheetParticipant: ChatParticipant?
    // Timeline grouping does per-message `Calendar` work; cache it so unrelated
    // store changes (a sidebar refresh) don't recompute it on every body pass.
    @State private var timelineCache = MemoizedValue<TimelineCacheKey, [TimelineEntry]>()
    // The read indicator scans every message (isOutgoing + isReadByOther); memoize
    // it so an unrelated store change doesn't re-scan the timeline on each body pass.
    @State private var readIndicatorCache = MemoizedValue<ReadIndicatorKey, String?>()
    private let bottomAnchorID = "bottom-id"

    var body: some View {
        if sessionStore.accessToken.isEmpty {
            TokenRequiredView(
                title: "No Chat Selected",
                systemImage: "bubble.left.and.bubble.right",
                description: "Add a token in Settings first."
            )
        } else if let selectedChat = chatStore.selectedChat {
            let messages = chatStore.messages(for: selectedChat.id)
            let timelineVersion = chatStore.messagesChatID == selectedChat.id ? chatStore.messagesVersion : -1
            let timelineEntries = timelineCache(TimelineCacheKey(version: timelineVersion, firstUnreadID: firstUnreadID)) {
                self.timelineEntries(for: messages)
            }
            let activeComposerMessageID = chatStore.activeComposerMessage?.id
            let readIndicatorMessageID = readIndicatorCache(
                ReadIndicatorKey(
                    version: timelineVersion,
                    lastReadByOtherSortKey: chatStore.lastReadByOtherSortKey,
                    selfParticipantID: selectedChat.participants?.items.first(where: { $0.isSelf == true })?.id
                )
            ) {
                self.lastReadOutgoingMessageID(messages: messages, chat: selectedChat)
            }

            ScrollViewReader { proxy in
                List {
                    if chatStore.hasMoreMessages(for: selectedChat.id) {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                            .onAppear {
                                guard !chatStore.isLoadingOlderMessages else { return }
                                loadOlderMessages(chatID: selectedChat.id, proxy: proxy)
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
                            if !entry.message.isEmptyDeleted && entry.message.isOutgoing(in: selectedChat) {
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

                    Color.clear
                        .modifier(TimelineFocusEffect(isFocused: activeComposerMessageID == nil))
                        .listRowInsets(.init())
                        .id(bottomAnchorID)
                }
                .task(id: selectedChat.id) {
                    isPreparingInitialScroll = true
                    firstUnreadID = nil
                    chatStore.setReplyTo(nil)
                    chatStore.cancelEditing()
                    async let detail: () = chatStore.loadChatDetail(for: selectedChat.id)
                    // The load itself is owned by the store (survives view churn);
                    // here we just wait for it to settle before sequencing scroll.
                    await chatStore.awaitCurrentMessagesLoad()
                    firstUnreadID = firstUnreadMessageID(messages: chatStore.messages(for: selectedChat.id), chat: selectedChat)
                    try? await Task.sleep(for: .milliseconds(50))
                    scrollToBottom(with: proxy, animated: false)
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                    isPreparingInitialScroll = false
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
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(50))
                        scrollToBottom(with: proxy, animated: true)
                        // 2026-06-06: same scar as iOS (2026-06-05) — re-grouping
                        // (prev bubble's isLastInGroup flips) and the debounced
                        // sidebar refresh re-measure rows after the animated
                        // scroll lands, leaving the list slightly off-bottom.
                        // Re-pin once layout settles.
                        try? await Task.sleep(for: .milliseconds(450))
                        scrollToBottom(with: proxy, animated: false)
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

    private func scrollToLinkedMessage(_ linkedID: String, chatID: String, proxy: ScrollViewProxy) {
        let messages = chatStore.messages(for: chatID)
        guard let target = messages.first(where: { $0.id == linkedID }) else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(target.timelineKey, anchor: .center)
        }
    }

    private func loadOlderMessages(chatID: String, proxy: ScrollViewProxy) {
        let anchorMessageID = chatStore.messages(for: chatID).first?.timelineKey
        Task { @MainActor in
            _ = await chatStore.loadOlderMessages(for: chatID)
            if let anchorMessageID {
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

/// Memoization key for the timeline grouping: it depends only on the timeline's
/// content (tracked by the store's O(1) version counter) and the unread divider's
/// position. `version` is -1 when no timeline is shown for the open chat yet.
private struct TimelineCacheKey: Equatable {
    let version: Int
    let firstUnreadID: String?
}

/// Memoization key for the "Read" indicator: it depends on the timeline content,
/// how far the other side has read, and who "self" is (which drives `isOutgoing`).
private struct ReadIndicatorKey: Equatable {
    let version: Int
    let lastReadByOtherSortKey: String?
    let selfParticipantID: String?
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
