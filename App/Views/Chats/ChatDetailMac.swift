#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct ChatDetailMac: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var inputManager
    @State private var showingChatInfo = false
    @State private var timelinePosition = ScrollPosition(idType: String.self)
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
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if chatStore.isLoadingOlderMessages {
                            ProgressView()
                                .frame(maxWidth: .infinity)

                        }

                        ForEach(timelineEntries) { entry in
                            VStack(spacing: 0) {
                                if entry.message.id == firstUnreadID {
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

                        Color.clear
                            .modifier(TimelineFocusEffect(isFocused: activeComposerMessageID == nil))

                            .frame(height: 24)
                            .id(bottomAnchorID)
                    }
                    .padding(.horizontal, 10)
                    .scrollTargetLayout()
                }
                // Recreate only the viewport when a chat opens or its first
                // database page arrives. Its first layout starts at the bottom.
                .id("\(selectedChat.id)-\(chatStore.hasLoadedTimeline(for: selectedChat.id))")
                // Initial layout and short conversations align to the bottom.
                // Content growth must preserve the starting offset so the
                // explicit send scroll can animate to its new destination.
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .alignment)
                .scrollPosition($timelinePosition)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top < 80
                } action: { _, nearTop in
                    guard nearTop, chatStore.hasLoadedTimeline(for: selectedChat.id),
                          !messages.isEmpty else { return }
                    loadOlderMessages(chatID: selectedChat.id)
                }
                .onChange(of: selectedChat.id, initial: true) { _, _ in
                    timelinePosition = ScrollPosition(idType: String.self)
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
                    // An edge position follows content growth, including the
                    // outgoing row's replacement by its confirmed message.
                    // Reissuing a nonanimated scroll here interrupts the send.
                    guard !confirmedOptimisticMessage else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        timelinePosition.scrollTo(edge: .bottom)
                    }
                }
                .onChange(of: activeComposerMessageID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(messages.first(where: { $0.id == newValue })?.timelineKey ?? newValue, anchor: .center)
                    }
                }
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

    private func loadOlderMessages(chatID: String) {
        guard chatStore.selectedChatID == chatID, chatStore.hasMoreMessages(for: chatID),
              !chatStore.isLoadingOlderMessages else { return }
        Task { @MainActor in
            // Stable scroll targets let SwiftUI preserve the visible messages
            // while older history is inserted above them.
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
