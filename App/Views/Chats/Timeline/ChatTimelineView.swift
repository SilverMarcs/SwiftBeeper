import SwiftUI
import UniformTypeIdentifiers

/// A timeline and its composer: the open chat's, or one of its threads'.
/// Message layout and scrolling are shared; the composer is `ComposerBar` on
/// iPhone and iPad and the inline `MessageInputView` on macOS.
struct ChatTimelineView<Source: TimelineSource>: View {
    let source: Source

    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var inputManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MessageTextSelection.storageKey) private var selectsMessageText = true
    @State private var firstUnreadID: String?
    @State private var isNearBottom = true
    /// Bumped by each scroll to the newest row; its completion only clears
    /// `isScrollingToLatest` when no newer scroll started meanwhile.
    @State private var latestScrollGeneration = 0
    /// True while the app animates to the newest row. A tall new row pushes
    /// the bottom out of reach until the scroll lands, and a burst of
    /// messages arriving meanwhile should keep following.
    @State private var isScrollingToLatest = false
    @State private var restingPosition = TimelineRestingPosition()
    /// The derived message rows, rebuilt only when their inputs change.
    @State private var entriesCache = TimelineEntriesCache()
    /// Long messages the reader chose to read in full.
    @State private var expandedMessages = ExpandedMessages()
    /// Keeps the reader's row in place when older pages land above it.
    @State private var scrollAnchor = TimelineScrollAnchor()
    /// The quoted message a tapped reply preview shows over the timeline.
    @State private var quotedMessage: QuotedMessageContext?
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
                readReceipts: source.readReceipts,
                groupMemberCount: chat.isGroupChat ? chat.participants.map { $0.total ?? $0.items.count } : nil,
                quotedMessages: source.quotedMessages,
                followingTypingSenderID: outgoingMessages.isEmpty ? typingBubble?.participant.id : nil
            )
            let outgoingTimelineEntries = OutgoingTimelineEntry.entries(for: outgoingMessages, following: messages)
            let confirmedCaption = entriesCache.deliveryCaption
            // A just-sent bubble lands before its caption appears below it,
            // as in Messages.
            let deliveryCaption = inputManager.sendAnimator.flights.isEmpty
                ? DeliveryIndicator.newest(outgoing: outgoingMessages, confirmed: confirmedCaption?.indicator)
                : nil
            let timelineItems = TimelineItem.items(
                messages: timelineEntries,
                outgoing: outgoingTimelineEntries,
                deliveryCaption: deliveryCaption,
                // An optimistic row's caption sits below it, at the end.
                deliveryCaptionRowID: outgoingMessages.isEmpty
                    ? confirmedCaption.map { TimelineEntry.rowID(for: $0.messageID, in: timelineEntries) }
                    : nil,
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
                                    .controlSize(.small)
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
                                // The caption comes and goes at once; the
                                // scroll below it is the motion.
                                .transition(item.isDeliveryCaption ? .identity : .opacity)
                                .onGeometryChange(for: CGRect.self) { geometry in
                                    geometry.frame(in: .scrollView)
                                } action: { frame in
                                    guard let rowID = item.scrollTargetID else { return }
                                    scrollAnchor.update(rowID, frame: frame)
                                }
                                .onDisappear {
                                    guard let rowID = item.scrollTargetID else { return }
                                    scrollAnchor.update(rowID, frame: nil)
                                }
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
                    .followsComposerOnKeyboard(composer, restingPosition: restingPosition)
                    .dismissesComposerOnTap { [composer] in
                        // Resigning at once, rather than through the composer's
                        // focus, lets UIKit announce the keyboard hiding before
                        // the composer starts to shrink.
                        guard composer.isFocused else { return }
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    #endif
                }
                .scrollDisabled(activeComposerMessageID != nil)
                .timelineSwipeActionsContainer()
                // Recreate only the viewport when a timeline opens or its first database page arrives
                // A message picked from search, once its page has loaded. The
                // rows just laid out, so let them settle before scrolling; a
                // viewport rebuilt for another stretch asks again on appearing.
                .onChange(of: source.messageRevealRequest, initial: true) { _, request in
                    guard let request else { return }
                    let rowID = TimelineEntry.rowID(for: request.messageID, in: timelineEntries)
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(rowID, anchor: .center)
                        }
                        source.finishMessageReveal()
                    }
                }
                .id("\(target.chatID)-\(target.threadRootID ?? "")-\(source.hasLoadedTimeline)-\(source.timelineWindowID)")
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
                    // A reader who scrolled back through the conversation
                    // stays where they are.
                    guard restingPosition.isAtEnd else { return }
                    scrollToLatest(with: proxy)
                } scrollToComposerMessage: { messageID in
                    scrollAboveKeyboard(messageID, with: proxy)
                }
                // The composer growing, as the keyboard comes up or the draft
                // gains a line, takes a timeline kept at its end along; the
                // keyboard follower draws the move in step with the composer.
                .onScrollGeometryChange(for: CGFloat.self, of: \.contentInsets.bottom) { oldInset, newInset in
                    guard newInset > oldInset, restingPosition.isAtEnd, activeComposerMessageID == nil else { return }
                    scrollToLatest(with: proxy, animated: false)
                }
                #endif
                // Load the next older page a screen ahead of the top, so it
                // usually lands before the reader gets there.
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top < geometry.containerSize.height
                } action: { _, nearTop in
                    guard nearTop, !messages.isEmpty else { return }
                    Task { await source.loadOlderTimeline() }
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    Self.isNearBottom(geometry)
                } action: { _, nearBottom in
                    isNearBottom = nearBottom
                }
                // A stretch that stops short of the newest loads its next
                // newer page a screen ahead of the bottom. The value is the
                // content height while that close, so a page too short to
                // move the reader away still asks for the next one.
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    let isNearEnd = geometry.contentSize.height - geometry.visibleRect.maxY < geometry.containerSize.height
                    return isNearEnd ? geometry.contentSize.height : 0
                } action: { _, nearEndHeight in
                    guard nearEndHeight > 0, source.hasMoreNewerTimeline else { return }
                    Task { await source.loadNewerTimeline() }
                }
                .onScrollGeometryChange(for: ScrollGeometry.self) { geometry in
                    geometry
                } action: { _, geometry in
                    scrollAnchor.update(geometry)
                }
                // Older rows or the history header changed above the reader:
                // put the row they were looking at back where it was.
                .onChange(of: TimelineTopTracker(
                    target: target,
                    firstRowID: timelineItems.first?.id,
                    isLoadingOlder: source.isLoadingOlderTimeline,
                    canLoadServerHistory: source.canLoadServerHistory
                )) { oldTop, newTop in
                    guard source.hasLoadedTimeline, oldTop.target == newTop.target, oldTop.firstRowID != nil,
                          let anchor = scrollAnchor.current() else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(anchor.rowID, anchor: anchor.anchor)
                    }
                }
                #if os(iOS)
                // Only the reader decides; a scroll of the app's own leaves it.
                // Mid-scroll counts as away, so a fling back through the
                // conversation isn't pulled down by a tap on the composer.
                .onScrollPhaseChange { _, phase, context in
                    switch phase {
                    case .tracking, .interacting, .decelerating:
                        restingPosition.isAtEnd = false
                    case .idle:
                        restingPosition.isAtEnd = Self.isNearBottom(context.geometry)
                    default:
                        break
                    }
                }
                #endif
                .onChange(of: typingBubble?.id) { _, newValue in
                    guard newValue != nil, isFollowingLatest else { return }
                    scrollToLatest(with: proxy)
                }
                .onChange(of: target, initial: true) { _, _ in
                    quotedMessage = nil
                    scrollAnchor.reset()
                    firstUnreadID = nil
                    isNearBottom = true
                    isScrollingToLatest = false
                    restingPosition.isAtEnd = true
                }
                .onChange(of: source.hasLoadedTimeline, initial: true) { _, loaded in
                    guard loaded, source.showsUnreadDivider else { return }
                    firstUnreadID = TimelineEntry.firstUnreadMessageID(in: messages, chat: chat)
                }
                .onChange(of: MessageListTracker(
                    count: messages.count + outgoingMessages.count,
                    lastID: outgoingMessages.last?.timelineKey ?? messages.last?.id,
                    stopsShortOfLatest: source.hasMoreNewerTimeline
                )) { oldTracker, newTracker in
                    guard source.hasLoadedTimeline, oldTracker.lastID != nil else { return }
                    // A newer page landing below the reader isn't a new
                    // message to follow down.
                    guard !oldTracker.stopsShortOfLatest else { return }
                    // Scroll when the newest row changes and the count did not
                    // shrink: pagination keeps lastID stable and deletions shrink
                    // the count, so both are skipped.
                    guard newTracker.lastID != oldTracker.lastID else { return }
                    guard newTracker.count >= oldTracker.count else { return }

                    let confirmedOptimisticMessage = oldTracker.lastID?.hasPrefix("outgoing-") == true
                        && newTracker.count == oldTracker.count
                    // Sending always brings the reader down to their message;
                    // anything else only follows a reader already at the end,
                    // so scrolling back through the conversation isn't undone.
                    let sentMessage = newTracker.lastID?.hasPrefix("outgoing-") == true
                    guard sentMessage || isFollowingLatest else { return }
                    firstUnreadID = nil
                    // Confirmation replaces the outgoing row, but not the end
                    // marker. Let the existing scroll animation finish.
                    guard !confirmedOptimisticMessage else { return }
                    scrollToLatest(with: proxy)
                }
                // A caption appearing below the newest row grows the timeline
                // under the reader, who follows it down if they were following
                // the conversation, as when "Delivered" appears in Messages.
                // Later steps replace its words in place and need no scroll.
                .onChange(of: TimelineDeliveryCaptionTracker(
                    target: target,
                    hasRows: !messages.isEmpty || !outgoingMessages.isEmpty,
                    showsCaption: deliveryCaption != nil
                )) { oldTracker, newTracker in
                    guard source.hasLoadedTimeline, oldTracker.target == newTracker.target, oldTracker.hasRows,
                          !oldTracker.showsCaption, newTracker.showsCaption, isFollowingLatest else { return }
                    scrollToLatest(with: proxy)
                }
                .onChange(of: activeComposerMessageID) { _, newValue in
                    guard let newValue else { return }
                    // Replying to or editing a message from the overlay
                    // returns to the timeline, where that message is focused.
                    dismissQuotedMessage()
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
                .overlay(alignment: .bottomTrailing) {
                    if source.hasMoreNewerTimeline {
                        JumpToLatestButton {
                            source.showLatestTimeline()
                        }
                    }
                }
                // Outside the scroll modifiers above, so they never pick up
                // a scroll view in the overlay's messages.
                .overlay {
                    if let quotedMessage {
                        QuotedMessageOverlay(context: quotedMessage, chat: rowChat, dismiss: dismissQuotedMessage)
                            .transition(.opacity)
                    }
                }
                .environment(\.showQuotedMessage, ShowQuotedMessageAction { quoted, reply in
                    let context = QuotedMessageContext(
                        quoted: quoted,
                        reply: reply,
                        entries: timelineEntries,
                        quotedMessages: source.quotedMessages
                    )
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        quotedMessage = context
                    }
                })
                .savesAttachments()
                .showsReactionDetails()
                #if os(iOS)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ComposerBar(composer: composer, chat: chat, error: source.timelineError)
                }
                #else
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    MessageInputView(composer: composer, chat: chat, error: source.timelineError)
                }
                #endif
                // The conversation's composer, for message actions such as Edit.
                .environment(\.composer, composer)
                .environment(\.expandedMessages, expandedMessages)
                .environment(\.selectsMessageText, selectsMessageText)
                .environment(\.selfMentionUserID, chatStore.currentUserProfile?.id)
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

    private static func isNearBottom(_ geometry: ScrollGeometry) -> Bool {
        geometry.visibleRect.maxY >= geometry.contentSize.height - 80
    }

    /// Whether the reader is at the newest row, or the app is already taking
    /// them there.
    private var isFollowingLatest: Bool {
        isNearBottom || isScrollingToLatest
    }

    private func dismissQuotedMessage() {
        guard quotedMessage != nil else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            quotedMessage = nil
        }
    }

    private func scrollToLatest(with proxy: ScrollViewProxy, animated: Bool = true) {
        latestScrollGeneration += 1
        let generation = latestScrollGeneration
        isScrollingToLatest = true
        withAnimation(reduceMotion || !animated ? nil : .easeOut(duration: 0.25)) {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        } completion: {
            guard generation == latestScrollGeneration else { return }
            isScrollingToLatest = false
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
    /// Whether the timeline held an older stretch of the conversation.
    let stopsShortOfLatest: Bool
}
