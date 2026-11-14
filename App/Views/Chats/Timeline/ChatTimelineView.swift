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
    @State private var selectableMessages = SelectableMessages()
    /// Keeps the reader's row in place when older pages land above it.
    @State private var scrollAnchor = TimelineScrollAnchor()
    /// Where rows sit, for the quoted messages a tapped quote moves up.
    @State private var rowFrames = TimelineRowFrames()
    /// The reply whose tapped quote the timeline focuses on, with the
    /// messages it quotes above it.
    @State private var quotedFocus: QuotedMessageFocus?
    /// The quote focus and chain length the timeline last made room for, so
    /// it scrolls once for each rather than on every frame of its own scroll.
    @State private var revealedQuotedChainKey: String?
    /// The timeline's top inset, under the header, where rows stop being visible.
    @State private var topContentInset: CGFloat = 0
    #if os(iOS)
    /// Brings a new reply or edit target above the composer once its context
    /// menu has dismissed.
    @State private var composerRevealTask: Task<Void, Never>?
    /// The reply or edit target the keyboard's rising safe area last placed
    /// above the composer, so the reveal above needn't place it again.
    @State private var keyboardPlacedMessageID: Message.ID?
    #endif
    private let bottomAnchorID = "timeline-bottom"

    var body: some View {
        if let chat = source.timelineChat, let target = source.composerTarget {
            let composer = inputManager.composer(for: target)
            let messages = source.timelineMessages
            let unreadID = firstUnreadID ?? source.messageRevealRequest.flatMap { $0.alignsTop ? $0.messageID : nil }
            let outgoingMessages = source.timelineOutgoingMessages
            let typingBubble = source.typingBubble
            let showsReadReceipts = chatStore.account(forAccountID: chat.accountID)?.showsReadReceipts == true
            let timelineEntries = entriesCache.entries(
                for: messages,
                firstUnreadID: unreadID,
                readReceipts: showsReadReceipts ? source.readReceipts : [],
                groupMemberCount: showsReadReceipts && chat.isGroupChat ? chat.participants.map { $0.total ?? $0.items.count } : nil,
                quotedMessages: source.quotedMessages,
                followingTypingSenderID: outgoingMessages.isEmpty ? typingBubble?.participant.id : nil,
                isThread: target.isThread,
                continuesIntoOutgoing: OutgoingTimelineEntry.continuesBubbles(
                    of: messages, into: outgoingMessages, isThread: target.isThread
                )
            )
            let outgoingTimelineEntries = OutgoingTimelineEntry.entries(
                for: outgoingMessages,
                following: messages,
                joinsLastRow: timelineEntries.last?.bubbleJoins.contains(.below) == true,
                isThread: target.isThread
            )
            let confirmedCaption = entriesCache.deliveryCaption
            // A just-sent bubble lands before its caption appears below it,
            // as in Messages.
            let deliveryCaption = inputManager.sendAnimator.flights.isEmpty
                ? DeliveryIndicator.newest(outgoing: outgoingMessages, confirmed: confirmedCaption?.indicator)
                : nil
            // A message the user is sending is newer than the one seen.
            let seenCaption = outgoingMessages.isEmpty ? entriesCache.newestSeenCaption : nil
            let timelineItems = TimelineItem.items(
                messages: timelineEntries,
                outgoing: outgoingTimelineEntries,
                deliveryCaption: deliveryCaption,
                // An optimistic row's caption sits below it, at the end.
                deliveryCaptionRowID: outgoingMessages.isEmpty
                    ? confirmedCaption.map { TimelineEntry.rowID(for: $0.messageID, in: timelineEntries) }
                    : nil,
                seenCaption: seenCaption,
                typing: source.hasLoadedTimeline ? typingBubble : nil,
                messageRowIDs: source.typingMessageRowIDs
            )
            let activeComposerMessageID = composer.activeMessage?.id
            // A quote stays shown only while its reply is in the timeline.
            let quoteFocus = quotedFocus.flatMap { focus in
                timelineEntries.contains { $0.id == focus.rowID } ? focus : nil
            }
            let quotedChain = quoteFocus.map {
                QuotedMessageChain.entries(from: $0.quoted, timeline: timelineEntries, quotedMessages: source.quotedMessages)
            } ?? []
            // The oldest quote in the chain, when it quotes one not loaded yet.
            let unresolvedQuote = quotedChain.first.flatMap { $0.linkedMessage == nil && $0.message.linkedMessageID?.isEmpty == false ? $0.message : nil }
            // The row the timeline focuses on, dimming the rest. A chain on
            // its way back to the timeline no longer holds it.
            let presentedQuoteFocus = quoteFocus?.isPresented == true ? quoteFocus : nil
            let quotedChainPresentation = quoteFocus.map { focus in
                let reply = timelineEntries.first { $0.id == focus.rowID }?.message
                return QuotedMessageChainPresentation(
                    id: focus.id, entries: quotedChain, origins: focus.origins,
                    senderName: focus.senderName == nil ? nil : reply,
                    senderNameOrigin: focus.senderName?.origin,
                    replySenderID: reply?.senderID,
                    headerHeight: topContentInset,
                    isPresented: focus.isPresented
                )
            }
            // Rows whose message the chain shows stand empty meanwhile, the
            // ones off screen at the tap included, as it may scroll them in.
            let quotedChainRowIDs = quoteFocus.map {
                QuotedMessageChain.rowIDs(of: quotedChain, in: timelineEntries, replyRowID: $0.rowID)
            } ?? []
            let quotedRoles = quoteFocus.map {
                QuotedFocusRowRole.roles(for: $0, chainRowIDs: quotedChainRowIDs)
            } ?? [:]
            let focusedRowID = presentedQuoteFocus?.rowID
                ?? activeComposerMessageID.map { TimelineEntry.rowID(for: $0, in: timelineEntries) }
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
                                let isQuoteReply = quoteFocus != nil && item.scrollTargetID == quoteFocus?.rowID
                                TimelineItemRow(
                                    item: item,
                                    chat: rowChat,
                                    firstUnreadID: outgoingMessages.isEmpty ? unreadID : nil,
                                    focusedRowID: focusedRowID,
                                    quotedChain: isQuoteReply ? quotedChainPresentation : nil,
                                    quotedFocusRole: item.scrollTargetID.flatMap { quotedRoles[$0] } ?? .none
                                )
                                .environment(\.timelineRowFrames, rowFrames)
                                // Its quotes float over the rows above it.
                                .zIndex(isQuoteReply ? 1 : 0)
                                // The caption comes and goes at once; the
                                // scroll below it is the motion.
                                .transition(item.isDeliveryCaption ? .identity : .opacity)
                                .onGeometryChange(for: CGRect.self) { geometry in
                                    geometry.frame(in: .scrollView)
                                } action: { frame in
                                    guard let rowID = item.scrollTargetID else { return }
                                    scrollAnchor.update(rowID, frame: frame)
                                    rowFrames.update(rowID, visibleFrame: frame)
                                }
                                .onDisappear {
                                    guard let rowID = item.scrollTargetID else { return }
                                    scrollAnchor.update(rowID, frame: nil)
                                    rowFrames.update(rowID, visibleFrame: nil)
                                    rowFrames.update(rowID, contentBottomEdge: nil)
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
                    // Where a quoted message's copy finds the row it moves
                    // from, however the timeline scrolls meanwhile.
                    .coordinateSpace(.timelineContent)
                    // Receded rows let taps through to this, which returns
                    // from a shown quote or a reply to the timeline. An edit
                    // ends only from its toolbar button, so a stray tap
                    // can't throw away the changes.
                    .background {
                        if let dismiss = dismissFocusAction(quoteFocus: presentedQuoteFocus, composer: composer) {
                            Button(dismiss.label, action: dismiss.callAsFunction)
                                .buttonStyle(TimelineFocusBackdropStyle(label: dismiss.label))
                                // The toolbar's Cancel Reply has the Escape
                                // key while replying.
                                .keyboardShortcut(presentedQuoteFocus != nil ? .cancelAction : nil)
                        }
                    }
                    .environment(\.dismissTimelineFocus, dismissFocusAction(
                        quoteFocus: presentedQuoteFocus,
                        composer: composer
                    ))
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
                .scrollDisabled(focusedRowID != nil)
                .timelineSwipeActionsContainer()
                .showsReactionPicker()
                // Recreate only the viewport when a timeline opens or its first database page arrives
                // A message picked from search, once its page has loaded. The
                // rows just laid out, so let them settle before scrolling; a
                // viewport rebuilt for another stretch asks again on appearing.
                .modifier(TimelineMessageReveal(
                    source: source, entries: timelineEntries, proxy: proxy,
                    frames: rowFrames, topInset: topContentInset
                ) {
                    latestScrollGeneration += 1
                    isScrollingToLatest = false
                    restingPosition.isAtEnd = false
                })
                .onScrollPhaseChange { _, phase in
                    guard phase == .tracking || phase == .interacting,
                          let request = source.messageRevealRequest,
                          request.isMention || request.alignsTop else { return }
                    source.finishMessageReveal(request, reached: false)
                    chatStore.mentionNavigation.dismissError()
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
                }
                // The composer growing, as the keyboard comes up or the draft
                // gains a line, keeps the message being replied to or edited
                // just above it, and otherwise takes a timeline kept at its
                // end along; the keyboard follower draws that move in step
                // with the composer. Following the safe area itself, rather
                // than focus, places the message however the keyboard came
                // up, including when a context menu brings it back.
                .onScrollGeometryChange(for: CGFloat.self, of: \.contentInsets.bottom) { oldInset, newInset in
                    guard newInset > oldInset else { return }
                    if let activeComposerMessageID {
                        keyboardPlacedMessageID = activeComposerMessageID
                        scrollAboveComposer(TimelineEntry.rowID(for: activeComposerMessageID, in: timelineEntries), with: proxy)
                    } else if restingPosition.isAtEnd {
                        scrollToLatest(with: proxy, animated: false)
                    }
                }
                #endif
                .onScrollGeometryChange(for: CGFloat.self, of: \.contentInsets.top) { _, inset in
                    topContentInset = inset
                }
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
                    rowFrames.containerHeight = geometry.containerSize.height
                }
                // Older rows or the history header changed above the reader:
                // put the row they were looking at back where it was.
                .onChange(of: TimelineTopTracker(
                    target: target,
                    firstRowID: timelineItems.first?.id,
                    isLoadingOlder: source.isLoadingOlderTimeline,
                    canLoadServerHistory: source.canLoadServerHistory
                )) { oldTop, newTop in
                    guard source.messageRevealRequest == nil, source.hasLoadedTimeline, oldTop.target == newTop.target, oldTop.firstRowID != nil,
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
                    quotedFocus = nil
                    revealedQuotedChainKey = nil
                    rowFrames.reset()
                    #if os(iOS)
                    composerRevealTask?.cancel()
                    #endif
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
                    captionCount: (deliveryCaption == nil ? 0 : 1) + (seenCaption == nil ? 0 : 1)
                )) { oldTracker, newTracker in
                    guard source.hasLoadedTimeline, oldTracker.target == newTracker.target, oldTracker.hasRows,
                          newTracker.captionCount > oldTracker.captionCount, isFollowingLatest else { return }
                    scrollToLatest(with: proxy)
                }
                .onChange(of: activeComposerMessageID) { _, newValue in
                    #if os(iOS)
                    composerRevealTask?.cancel()
                    #endif
                    guard let newValue else { return }
                    // Replying to or editing a quoted message returns to the
                    // timeline, where that message is focused.
                    dismissQuotedMessage()
                    let rowID = TimelineEntry.rowID(for: newValue, in: timelineEntries)
                    #if os(iOS)
                    // The keyboard rising places the message as its safe area
                    // arrives. With the keyboard already up, nothing else
                    // will, so place it once the context menu has dismissed:
                    // moving it sooner sends the menu's preview back to where
                    // the message was. With the keyboard down, placing it
                    // first would move it to the bottom just before the
                    // keyboard moves it again, so wait for the keyboard and
                    // place it only if none came, as with a hardware keyboard.
                    let waitsForKeyboard = !composer.isFocused
                    keyboardPlacedMessageID = nil
                    composerRevealTask = Task {
                        do {
                            try await Task.sleep(for: InputManager.contextMenuDismissalDelay
                                + (waitsForKeyboard ? Self.keyboardArrivalAllowance : .zero))
                        } catch {
                            return
                        }
                        guard composer.activeMessage?.id == newValue,
                              !(waitsForKeyboard && keyboardPlacedMessageID == newValue) else { return }
                        scrollAboveComposer(rowID, with: proxy)
                    }
                    #else
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(rowID, anchor: .center)
                    }
                    #endif
                }
                // Each quote the chain reaches that isn't loaded is read in
                // turn, so the chain grows until it's whole.
                .task(id: unresolvedQuote?.id) {
                    guard let unresolvedQuote else { return }
                    await source.loadQuotedMessages(for: [unresolvedQuote])
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
                    let canShow = source.hasLoadedTimeline && focusedRowID == nil && source.messageRevealRequest?.alignsTop != true
                    TimelineNavigationButton(
                        mentions: canShow && !target.isThread ? chatStore.mentionNavigation : nil,
                        showsLatest: canShow && (source.hasMoreNewerTimeline || !isNearBottom),
                        nextMention: { Task { await chatStore.revealNextMention() } },
                        jumpToLatest: {
                            if let request = source.messageRevealRequest, request.alignsTop {
                                source.finishMessageReveal(request, reached: false)
                            }
                            if source.hasMoreNewerTimeline {
                                source.showLatestTimeline()
                            } else {
                                scrollToLatest(with: proxy)
                            }
                        }
                    )
                }
                #if os(iOS)
                // Above the composer, in the safe area it and the keyboard
                // leave, without changing the composer's height.
                .overlay(alignment: .bottom) {
                    ComposerMentionSuggestions(composer: composer)
                }
                #endif
                .environment(\.showQuotedMessage, ShowQuotedMessageAction { quoted, reply in
                    // Optimistic rows have no reply to stay in place, and a
                    // reply or edit keeps the timeline's focus.
                    guard let reply, composer.activeMessage == nil else { return }
                    let rowID = TimelineEntry.rowID(for: reply.id, in: timelineEntries)
                    let chain = QuotedMessageChain.entries(from: quoted, timeline: timelineEntries, quotedMessages: source.quotedMessages)
                    // Quoted messages on screen move up from their rows;
                    // with Reduce Motion every one fades in.
                    let origins = reduceMotion ? [:] : rowFrames.visibleBottomEdges(
                        of: QuotedMessageChain.rowIDs(of: chain, in: timelineEntries, replyRowID: rowID)
                    )
                    let sender = QuotedSenderHandoff.handoffs(
                        for: rowID, in: timelineEntries, chat: chat, frames: reduceMotion ? nil : rowFrames
                    )
                    revealedQuotedChainKey = nil
                    withAnimation(ChatVisualStyle.quotedMessageAnimation(reduceMotion: reduceMotion)) {
                        quotedFocus = QuotedMessageFocus(
                            rowID: rowID, quoted: quoted, origins: origins,
                            senderName: sender.name, senderAvatar: sender.avatar
                        )
                    }
                })
                // A chain reaching above the header moves its reply down,
                // as far as the bottom, to make room for it.
                .environment(\.revealQuotedMessageChain, RevealQuotedMessageChainAction { top, count in
                    guard let quoteFocus = presentedQuoteFocus, top < topContentInset else { return }
                    let key = "\(quoteFocus.rowID)-\(count)"
                    guard revealedQuotedChainKey != key else { return }
                    revealedQuotedChainKey = key
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                        proxy.scrollTo(quoteFocus.rowID, anchor: .bottom)
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
                .environment(\.selectableMessages, selectableMessages)
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

    /// What a tap around the focused messages returns from: a shown quote,
    /// or else a reply. Nil while editing or when nothing is focused.
    private func dismissFocusAction(quoteFocus: QuotedMessageFocus?, composer: Composer) -> DismissTimelineFocusAction? {
        if let quoteFocus {
            return DismissTimelineFocusAction(id: "quote-\(quoteFocus.rowID)", label: "Close", action: dismissQuotedMessage)
        }
        if let reply = composer.replyingTo, !composer.isEditing {
            return DismissTimelineFocusAction(id: "reply-\(reply.id)", label: "Cancel Reply") { [inputManager] in
                inputManager.cancelAction(in: composer)
            }
        }
        return nil
    }

    /// Sends the chain's messages back to their rows, then removes it.
    private func dismissQuotedMessage() {
        guard let focus = quotedFocus, focus.isPresented else { return }
        withAnimation(ChatVisualStyle.quotedMessageAnimation(reduceMotion: reduceMotion)) {
            quotedFocus?.isPresented = false
        } completion: {
            // A quote tapped meanwhile keeps its own chain.
            guard quotedFocus?.id == focus.id else { return }
            quotedFocus = nil
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
    /// How long after its focus request a reply's or edit's keyboard may
    /// take to start rising: the composer asks for focus for this long.
    private static var keyboardArrivalAllowance: Duration { .milliseconds(600) }

    /// Aligns the reply/edit target's bottom edge with the composer, above
    /// the keyboard when it's up. A message taller than the viewport keeps
    /// its end visible.
    private func scrollAboveComposer(_ rowID: Message.ID, with proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            proxy.scrollTo(rowID, anchor: .bottom)
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
