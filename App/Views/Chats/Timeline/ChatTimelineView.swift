import SwiftUI
import UniformTypeIdentifiers

/// Shared message layout and scrolling, with platform-specific navigation and composers.
struct ChatTimelineView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var inputManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var firstUnreadID: String?
    @State private var isNearBottom = true
    private let bottomAnchorID = "timeline-bottom"

    var body: some View {
        if let selectedChat = chatStore.selectedChat {
            let messages = chatStore.timelineMessages
            let outgoingMessages = chatStore.outgoingMessages
            let timelineEntries = TimelineEntry.entries(
                for: messages,
                firstUnreadID: firstUnreadID,
                lastReadByOtherSortKey: chatStore.lastReadByOtherSortKey,
                followingTypingSenderID: outgoingMessages.isEmpty ? chatStore.typingBubble?.participant.id : nil
            )
            let outgoingTimelineEntries = OutgoingTimelineEntry.entries(for: outgoingMessages, following: messages)
            let timelineItems = TimelineItem.items(
                messages: timelineEntries,
                outgoing: outgoingTimelineEntries,
                typing: chatStore.hasLoadedTimeline ? chatStore.typingBubble : nil,
                messageRowIDs: chatStore.typingMessageRowIDs
            )
            let activeComposerMessageID = chatStore.activeComposerMessage?.id

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        LazyVStack(spacing: 0) {
                            if chatStore.isLoadingOlderMessages {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            }

                            ForEach(timelineItems) { item in
                                TimelineItemRow(
                                    item: item,
                                    chat: selectedChat,
                                    firstUnreadID: outgoingMessages.isEmpty ? firstUnreadID : nil,
                                    activeComposerMessageID: activeComposerMessageID
                                )
                                .transition(.opacity)
                            }
                        }
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: ChatVisualStyle.typingBubbleExpansionDuration),
                            value: chatStore.typingBubble?.id
                        )
                        // Keep the scroll target available independently of lazy rows.
                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                            .accessibilityHidden(true)
                    }
                    #if os(iOS)
                    .if(isIPhone) {
                        $0.followsComposerOnKeyboard()
                    }
                    #endif
                }
                .scrollDisabled(activeComposerMessageID != nil)
                .environment(\.scrollToMessage, ScrollToMessageAction { messageID in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(messageID, anchor: .center)
                    }
                })
                .savesAttachments()
                // Recreate only the viewport when a chat opens or its first database page arrives
                .id("\(selectedChat.id)-\(chatStore.hasLoadedTimeline)")
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .alignment)
                .contentMargins(.horizontal, 10, for: .scrollContent)
                .contentMargins(.bottom, 24, for: .scrollContent)
                .scrollClipDisabled(!inputManager.sendAnimator.flights.isEmpty)
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                .scrollsOnComposerFocus(chatID: selectedChat.id) {
                    scrollToLatest(with: proxy)
                } scrollToComposerMessage: { messageID in
                    scrollAboveKeyboard(messageID, with: proxy)
                }
                #endif
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top < 80
                } action: { _, nearTop in
                    guard nearTop, !messages.isEmpty else { return }
                    Task { await chatStore.loadOlderMessages() }
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.visibleRect.maxY >= geometry.contentSize.height - 80
                } action: { _, nearBottom in
                    isNearBottom = nearBottom
                }
                .onChange(of: chatStore.typingBubble?.id) { _, newValue in
                    guard newValue != nil, isNearBottom else { return }
                    scrollToLatest(with: proxy)
                }
                .onChange(of: selectedChat.id, initial: true) { _, _ in
                    firstUnreadID = nil
                    isNearBottom = true
                }
                .onChange(of: chatStore.hasLoadedTimeline, initial: true) { _, loaded in
                    guard loaded else { return }
                    firstUnreadID = TimelineEntry.firstUnreadMessageID(in: messages, chat: selectedChat)
                }
                .onChange(of: MessageListTracker(
                    count: messages.count + outgoingMessages.count,
                    lastID: outgoingMessages.last?.timelineKey ?? messages.last?.id
                )) { oldTracker, newTracker in
                    guard chatStore.hasLoadedTimeline, oldTracker.lastID != nil else { return }
                    // Scroll when the newest row changes and the count did not
                    // shrink: pagination keeps lastID stable and deletions shrink
                    // the count, so both are skipped.
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
                    #if os(iOS)
                    // With the keyboard already up no focus change follows, so
                    // place the target now. Otherwise ScrollOnComposerFocus
                    // places it once the keyboard rises, leaving it untouched
                    // while the context menu dismisses.
                    guard inputManager.isComposerFocused else { return }
                    scrollAboveKeyboard(newValue, with: proxy)
                    #else
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                    #endif
                }
                .animation(.default, value: activeComposerMessageID)
                .overlay {
                    if !chatStore.hasLoadedTimeline,
                       let error = chatStore.messagesError, !chatStore.isLoadingMessages {
                        ContentUnavailableView {
                            Label("Couldn’t Load Messages", systemImage: "exclamationmark.bubble")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("Try Again") {
                                Task { await chatStore.loadMessages() }
                            }
                        }
                    }
                }
                #if os(iOS)
                .if(isIPhone) {
                    $0.searchFieldComposer()
                }
                #endif
                .if(isMacOrPad) {
                    // macOS and iPad share the inline composer.
                    $0.safeAreaBar(edge: .bottom, spacing: 0) {
                        MessageInputView()
                    }
                }
                .onDrop(of: [.item], isTargeted: nil) { providers in
                    inputManager.handleDrop(providers)
                }
                .alert("Couldn’t Attach Item", isPresented: Binding(
                    get: { inputManager.attachmentImportError != nil },
                    set: { if !$0 { inputManager.attachmentImportError = nil } }
                )) {
                    Button("OK") { inputManager.attachmentImportError = nil }
                } message: {
                    Text(inputManager.attachmentImportError ?? "")
                }
            }
            .modifier(ComposerDictationLifecycle())
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
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }

    #if os(iOS)
    /// Aligns the reply/edit target's bottom edge with the composer above the
    /// keyboard. A message taller than the viewport keeps its end visible.
    private func scrollAboveKeyboard(_ messageID: Message.ID, with proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(messageID, anchor: .bottom)
        }
    }
    #endif
}

/// The newest row and the row count, which together tell a new message from
/// pagination, deletion, and an optimistic row's confirmation.
private struct MessageListTracker: Equatable {
    let count: Int
    let lastID: String?
}
