import SwiftUI
import UniformTypeIdentifiers

/// A timeline and its composer: the open chat's, or one of its threads'.
/// Message layout and scrolling are shared; the composer is the navigation
/// search field on iPhone and the inline composer on macOS and iPad.
struct ChatTimelineView<Source: TimelineSource>: View {
    let source: Source

    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var inputManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var firstUnreadID: String?
    @State private var isNearBottom = true
    /// The derived message rows, rebuilt only when their inputs change.
    @State private var entriesCache = TimelineEntriesCache()
    private let bottomAnchorID = "timeline-bottom"

    var body: some View {
        if let chat = source.timelineChat, let target = source.composerTarget {
            let composer = inputManager.composer(for: target)
            let messages = source.timelineMessages
            let outgoingMessages = source.timelineOutgoingMessages
            let typingBubble = source.typingBubble
            let timelineEntries = entriesCache.entries(
                for: messages,
                firstUnreadID: firstUnreadID,
                lastReadByOtherSortKey: source.lastReadByOtherSortKey,
                quotedMessages: source.quotedMessages,
                followingTypingSenderID: outgoingMessages.isEmpty ? typingBubble?.participant.id : nil
            )
            let outgoingTimelineEntries = OutgoingTimelineEntry.entries(for: outgoingMessages, following: messages)
            let timelineItems = TimelineItem.items(
                messages: timelineEntries,
                outgoing: outgoingTimelineEntries,
                typing: source.hasLoadedTimeline ? typingBubble : nil,
                messageRowIDs: source.typingMessageRowIDs
            )
            let activeComposerMessageID = composer.activeMessage?.id
            // Rows get the chat without its preview and unread state, so each
            // new message or read doesn't re-render every row.
            let rowChat = chat.forTimelineRows

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        LazyVStack(spacing: 0) {
                            if source.isLoadingOlderTimeline {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else if source.canLoadServerHistory {
                                LoadServerHistoryButton {
                                    await source.loadServerHistory()
                                }
                            }

                            ForEach(timelineItems) { item in
                                TimelineItemRow(
                                    item: item,
                                    chat: rowChat,
                                    firstUnreadID: outgoingMessages.isEmpty ? firstUnreadID : nil,
                                    activeComposerMessageID: activeComposerMessageID
                                )
                                .transition(.opacity)
                            }
                        }
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: ChatVisualStyle.typingBubbleExpansionDuration),
                            value: typingBubble?.id
                        )
                        // Keep the scroll target available independently of lazy rows.
                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                            .accessibilityHidden(true)
                    }
                    #if os(iOS)
                    .if(isIPhone) {
                        $0.followsComposerOnKeyboard(composer)
                    }
                    #endif
                }
                .scrollDisabled(activeComposerMessageID != nil)
                .environment(\.scrollToMessage, ScrollToMessageAction { messageID in
                    // A reply to a folded-in photo jumps to its gallery row.
                    let rowID = TimelineEntry.rowID(for: messageID, in: timelineEntries)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(rowID, anchor: .center)
                    }
                })
                .savesAttachments()
                .showsReactionDetails()
                // Recreate only the viewport when a timeline opens or its first database page arrives
                .id("\(target.chatID)-\(target.threadRootID ?? "")-\(source.hasLoadedTimeline)")
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .alignment)
                #if os(macOS)
                .contentMargins(.horizontal, 15, for: .scrollContent)
                #else
                .contentMargins(.horizontal, 12, for: .scrollContent)
                #endif
                .contentMargins(.bottom, 24, for: .scrollContent)
                .scrollClipDisabled(!inputManager.sendAnimator.flights.isEmpty)
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                .scrollsOnComposerFocus(composer) {
                    scrollToLatest(with: proxy)
                } scrollToComposerMessage: { messageID in
                    scrollAboveKeyboard(messageID, with: proxy)
                }
                #endif
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top < 80
                } action: { _, nearTop in
                    guard nearTop, !messages.isEmpty else { return }
                    Task { await source.loadOlderTimeline() }
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.visibleRect.maxY >= geometry.contentSize.height - 80
                } action: { _, nearBottom in
                    isNearBottom = nearBottom
                }
                .onChange(of: typingBubble?.id) { _, newValue in
                    guard newValue != nil, isNearBottom else { return }
                    scrollToLatest(with: proxy)
                }
                .onChange(of: target, initial: true) { _, _ in
                    firstUnreadID = nil
                    isNearBottom = true
                }
                .onChange(of: source.hasLoadedTimeline, initial: true) { _, loaded in
                    guard loaded, source.showsUnreadDivider else { return }
                    firstUnreadID = TimelineEntry.firstUnreadMessageID(in: messages, chat: chat)
                }
                .onChange(of: MessageListTracker(
                    count: messages.count + outgoingMessages.count,
                    lastID: outgoingMessages.last?.timelineKey ?? messages.last?.id
                )) { oldTracker, newTracker in
                    guard source.hasLoadedTimeline, oldTracker.lastID != nil else { return }
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
                    guard composer.isFocused else { return }
                    scrollAboveKeyboard(newValue, with: proxy)
                    #else
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                    #endif
                }
                .animation(.default, value: activeComposerMessageID)
                .overlay {
                    if !source.hasLoadedTimeline,
                       let error = source.timelineError, !source.isLoadingTimeline {
                        ContentUnavailableView {
                            Label("Couldn’t Load Messages", systemImage: "exclamationmark.bubble")
                        } description: {
                            Text(error)
                        } actions: {
                            Button("Try Again") {
                                Task { await source.loadTimeline() }
                            }
                        }
                    }
                }
                #if os(iOS)
                .if(isIPhone) {
                    $0.searchFieldComposer(composer, chat: chat)
                }
                #endif
                .if(isMacOrPad) {
                    // macOS and iPad share the inline composer.
                    $0.safeAreaBar(edge: .bottom, spacing: 0) {
                        MessageInputView(composer: composer, chat: chat, error: source.timelineError)
                    }
                }
                // The conversation's composer, for message actions such as Edit.
                .environment(\.composer, composer)
                // Covers the composer too, so Send matches the bubbles it sends.
                .environment(\.outgoingBubbleColor, MessagingNetwork(accountID: chat.accountID).outgoingBubbleColor)
                .onDrop(of: [.item], isTargeted: nil) { providers in
                    inputManager.handleDrop(providers, into: composer)
                }
                .alert("Couldn’t Attach Item", isPresented: Binding(
                    get: { composer.attachmentImportError != nil },
                    set: { if !$0 { composer.attachmentImportError = nil } }
                )) {
                    Button("OK") { composer.attachmentImportError = nil }
                } message: {
                    Text(composer.attachmentImportError ?? "")
                }
            }
            .modifier(ComposerDictationLifecycle(composer: composer))
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
