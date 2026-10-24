import SwiftUI
import UniformTypeIdentifiers

/// Shared message layout and scrolling, with platform-specific navigation and composers.
struct ChatTimelineView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var inputManager
    #if os(iOS)
    /// The iPhone search-field composer's focus.
    @FocusState private var isSearchFocused: Bool
    @State private var keyboardScrollTask: Task<Void, Never>?
    #endif
    @State private var firstUnreadID: String?
    private let bottomAnchorID = "timeline-bottom"

    var body: some View {
        if let selectedChat = chatStore.selectedChat {
            let messages = chatStore.timelineMessages
            let outgoingMessages = chatStore.outgoingMessages
            let timelineEntries = TimelineEntry.entries(
                for: messages,
                firstUnreadID: firstUnreadID,
                lastReadByOtherSortKey: chatStore.lastReadByOtherSortKey
            )
            let outgoingTimelineEntries = OutgoingTimelineEntry.entries(for: outgoingMessages, following: messages)
            let activeComposerMessageID = chatStore.activeComposerMessage?.id

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        LazyVStack(spacing: 0) {
                            if chatStore.isLoadingOlderMessages {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            }

                            ForEach(timelineEntries) { entry in
                                TimelineEntryRow(
                                    entry: entry,
                                    chat: selectedChat,
                                    showsUnreadDivider: entry.message.id == firstUnreadID && outgoingMessages.isEmpty,
                                    activeComposerMessageID: activeComposerMessageID
                                )
                                .id(entry.id)
                            }

                            ForEach(outgoingTimelineEntries) { entry in
                                OutgoingTimelineEntryRow(entry: entry, activeComposerMessageID: activeComposerMessageID)
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
                .environment(\.scrollToMessage, ScrollToMessageAction { messageID in
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(messageID, anchor: .center)
                    }
                })
                .savesAttachments()
                // Recreate only the viewport when a chat opens or its first
                // database page arrives. Its first layout starts at the bottom.
                .id("\(selectedChat.id)-\(chatStore.hasLoadedTimeline)")
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
                    guard nearTop, !messages.isEmpty else { return }
                    Task { await chatStore.loadOlderMessages() }
                }
                .onChange(of: selectedChat.id, initial: true) { _, _ in
                    firstUnreadID = nil
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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
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
                .onDrop(of: [.item], isTargeted: nil) { providers in
                    inputManager.handleDrop(providers)
                }
                #if os(iOS)
                .if(isIPhone) {
                    $0.searchFieldComposer(isFocused: $isSearchFocused)
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
}

/// The newest row and the row count, which together tell a new message from
/// pagination, deletion, and an optimistic row's confirmation.
private struct MessageListTracker: Equatable {
    let count: Int
    let lastID: String?
}
