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
    @Environment(\.scenePhase) private var scenePhase
    @State private var firstUnreadID: String?
    @State private var incomingMessageIDs: Set<Message.ID> = []
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
    private let topAnchorID = "timeline-top"
    private let bottomAnchorID = "timeline-bottom"

    var body: some View {
        if let chat = source.timelineChat, let target = source.composerTarget {
            let composer = inputManager.composer(for: target)
            let messages = source.timelineMessages
            let unreadID = firstUnreadID ?? source.messageRevealRequest.flatMap { $0.alignsTop ? $0.messageID : nil }
            let outgoingMessages = source.timelineOutgoingMessages
            let typingBubble = source.typingBubble
            // A large group's receipts say too little to show: its captions
            // fall back to whether the newest message was sent, as Slack's do.
            let showsReadReceipts = chatStore.account(forAccountID: chat.accountID)?.showsReadReceipts == true
                && !chat.isLargeGroup
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
            // Reserve the caption's space before the flight starts, then
            // reveal it on landing without moving the bubble a second time.
            let hidesDeliveryCaption = !inputManager.sendAnimator.flights.isEmpty
            let deliveryCaption = DeliveryIndicator.newest(outgoing: outgoingMessages, confirmed: confirmedCaption?.indicator)
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
                            // Where a timeline shorter than the view rests.
                            Color.clear
                                .frame(height: 0)
                                .id(topAnchorID)
                                .accessibilityHidden(true)

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
                                    hidesDeliveryCaption: hidesDeliveryCaption,
                                    quotedChain: isQuoteReply ? quotedChainPresentation : nil,
                                    quotedFocusRole: item.scrollTargetID.flatMap { quotedRoles[$0] } ?? .none
                                )
                                .modifier(TimelineSeenMessages(
                                    item: item, isPresented: !target.isThread || chatStore.isThreadPresented
                                ))
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
                                    if rowFrames.isVisible(rowID, below: topContentInset) {
                                        chatStore.mentionNavigation.didSee(rowID)
                                    }
                                }
                                .onDisappear {
                                    guard let rowID = item.scrollTargetID else { return }
                                    scrollAnchor.update(rowID, frame: nil)
                                    rowFrames.update(rowID, visibleFrame: nil)
                                    rowFrames.update(rowID, contentBottomEdge: nil)
                                }
                            }

                            // The end is the lazy stack's own last row, so
                            // scrolling to it lays out the rows above it from
                            // the end. Placed after the stack, it would sit
                            // where the stack's estimate of the rows above
                            // ends, and once those rows were measured shorter
                            // SwiftUI would leave the rows in view undrawn.
                            Color.clear
                                .frame(height: 1)
                                .id(bottomAnchorID)
                                .accessibilityHidden(true)
                        }
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: ChatVisualStyle.typingBubbleExpansionDuration),
                            value: typingBubble?.id
                        )
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
                .onScrollPhaseChange { _, phase in
                    restingPosition.isScrolling = phase != .idle
                    if phase == .tracking || phase == .interacting {
                        restingPosition.settlesAtEndUntil = nil
                    }
                }
                .onAppear {
                    // A viewport rebuilt mid-scroll never reports landing.
                    restingPosition.isScrolling = false
                    restingPosition.settlesAtEndUntil = nil
                    // A chat opens at its newest messages. Going to the end
                    // target, the lazy stack's own last row, lays the rows
                    // out from there.
                    guard source.hasLoadedTimeline, !source.hasMoreNewerTimeline,
                          source.messageRevealRequest == nil else { return }
                    scrollToLatest(with: proxy, animated: false)
                    #if os(macOS)
                    // On iOS the first scroll lands at the end, and the
                    // keyboard follower moves the timeline as it opens.
                    restingPosition.settlesAtEndUntil = .now + Self.endSettlingWindow
                    #endif
                }
                // Rebuilt when the first page arrives, so a chat opened
                // before its messages lands at their end like one opened
                // after them.
                .id("\(target.chatID)-\(target.threadRootID ?? "")-\(source.hasLoadedTimeline)-\(source.timelineWindowID)")
                // No default anchor: the timeline goes to its end itself as
                // it opens, and content shorter than the view rests at its
                // top. Aligning that content to the bottom gives the scroll
                // view a top inset, and SwiftUI moves the offset by as much as
                // the inset changes, as the keyboard and composer come and go
                // or messages arrive, past where it can rest.
                #if os(macOS)
                .contentMargins(.horizontal, 15, for: .scrollContent)
                #else
                .contentMargins(.horizontal, 12, for: .scrollContent)
                #endif
                .contentMargins(.bottom, 24, for: .scrollContent)
                #if os(iOS)
                .scrollDismissesKeyboard(.interactively)
                .scrollsOnComposerFocus(composer) {
                    // A reader who scrolled back through the conversation
                    // stays where they are.
                    guard restingPosition.isAtEnd else { return }
                    scrollToLatest(with: proxy)
                }
                .onChange(of: source.messageRevealRequest) { oldRequest, newRequest in
                    // An unanimated reveal, or one already at its target,
                    // may never change scroll phase. Remember where it landed
                    // even when there is no idle transition to update it.
                    guard oldRequest != nil, newRequest == nil,
                          !restingPosition.isScrolling else { return }
                    restingPosition.isAtEnd = isNearBottom
                }
                #endif
                // Whether the content fits in the view, which decides where a
                // scroll to its end goes; see `scrollToBottom`.
                //
                // On iOS, the composer growing, as the keyboard comes up or
                // the draft gains a line, keeps the message being replied to
                // or edited just above it, and otherwise takes a timeline kept
                // at its end along; the keyboard follower draws that move in
                // step with the composer. Following the safe area itself,
                // rather than focus, places the message however the keyboard
                // came up, including when a context menu brings it back.
                .onScrollGeometryChange(for: InsetFitting.self) { geometry in
                    InsetFitting(inset: geometry.contentInsets.bottom, fits: Self.contentFits(geometry))
                } action: { oldValue, newValue in
                    // Set first: the scroll below goes by whether the content
                    // still fits the view the composer just shrank.
                    restingPosition.contentFits = newValue.fits
                    #if os(iOS)
                    guard newValue.inset > oldValue.inset else { return }
                    if let activeComposerMessageID {
                        keyboardPlacedMessageID = activeComposerMessageID
                        scrollAboveComposer(TimelineEntry.rowID(for: activeComposerMessageID, in: timelineEntries), with: proxy)
                    } else if restingPosition.isAtEnd {
                        scrollToLatest(with: proxy, animated: false)
                    }
                    #endif
                }
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
                    // Read from the whole geometry rather than a transform
                    // of its own: on macOS, that one could miss the lazy
                    // stack measuring rows shorter as a chat opens, leaving
                    // Jump to Latest up at the end.
                    let nearBottom = Self.isNearBottom(geometry)
                    if nearBottom != isNearBottom {
                        isNearBottom = nearBottom
                    }
                    settleAtEnd(geometry, focusedRowID: focusedRowID, with: proxy)
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
                    incomingMessageIDs = []
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
                .environment(\.incomingMessageIDs, incomingMessageIDs)
                .onChange(of: TimelineIncomingTracker(
                    target: target,
                    windowID: source.timelineWindowID,
                    isLoaded: source.hasLoadedTimeline,
                    hasMoreNewer: source.hasMoreNewerTimeline,
                    lastMessageID: messages.last?.id,
                    lastSortKey: messages.last?.numericSortKey
                )) { previous, current in
                    guard scenePhase == .active, isFollowingLatest,
                          focusedRowID == nil, source.messageRevealRequest == nil else { return }
                    incomingMessageIDs = current.arrivals(since: previous, in: messages)
                }
                .task(id: incomingMessageIDs) {
                    guard !incomingMessageIDs.isEmpty else { return }
                    do {
                        // Lazy history rows mustn't replay arrivals on a later scroll.
                        try await Task.sleep(for: .milliseconds(600))
                        incomingMessageIDs = []
                    } catch {
                        // A newer arrival or another viewport owns the state now.
                    }
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
                    // Make room smoothly while the bubble springs into place.
                    scrollToLatest(with: proxy, animation: sentMessage ? MessageSendMotion.scrollAnimation : nil)
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
                          newTracker.captionCount > oldTracker.captionCount, isFollowingLatest,
                          inputManager.sendAnimator.flights.isEmpty else { return }
                    // A send already scrolls to the space reserved for its
                    // caption during the flight.
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
                        scrollToBottom(of: quoteFocus.rowID, with: proxy)
                    }
                })
                .savesAttachments()
                .showsReactionDetails()
                #if os(iOS)
                .timelineComposerBar(composer, chat: chat, error: source.timelineError)
                #else
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    MessageInputView(composer: composer, chat: chat, error: source.timelineError)
                }
                #endif
                // Above the composer, so a sent message's bubble grows out of
                // the field itself rather than from under its glass.
                .overlayPreferenceValue(MessageSendDestinationKey.self) { destinations in
                    MessageSendFlightLayer(destinations: destinations)
                }
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
            .modifier(TimelineSeenMentions(
                mentions: chatStore.mentionNavigation, frames: rowFrames, topInset: topContentInset
            ))
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

    /// Whether all the content fits between the bars and the composer.
    private static func contentFits(_ geometry: ScrollGeometry) -> Bool {
        geometry.contentSize.height <= geometry.containerSize.height
    }

    /// How long after opening the timeline keeps going back to its end.
    private static var endSettlingWindow: Duration { .seconds(1) }

    /// A chat that just opened at its end goes back there when measuring its
    /// rows moved the end away: the first scroll lands where the lazy stack
    /// estimated the end, and a page of older messages loading as it opens
    /// keeps the rows in view rather than the end.
    private func settleAtEnd(_ geometry: ScrollGeometry, focusedRowID: Message.ID?, with proxy: ScrollViewProxy) {
        guard let deadline = restingPosition.settlesAtEndUntil else { return }
        guard ContinuousClock.now < deadline, focusedRowID == nil,
              source.messageRevealRequest == nil, !source.hasMoreNewerTimeline else {
            restingPosition.settlesAtEndUntil = nil
            return
        }
        // The app's own animated scroll to a new message is on its way there.
        guard !restingPosition.isScrolling else { return }
        let distanceFromEnd = geometry.contentSize.height + geometry.contentInsets.bottom - geometry.visibleRect.maxY
        guard !Self.contentFits(geometry), abs(distanceFromEnd) > 1 else { return }
        // After this geometry update rather than inside it: SwiftUI doesn't
        // report where a scroll made during it lands.
        Task { @MainActor in
            guard restingPosition.settlesAtEndUntil != nil, !restingPosition.isScrolling else { return }
            scrollToLatest(with: proxy, animated: false)
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

    /// - Parameter animation: How to scroll, rather than easing out.
    private func scrollToLatest(with proxy: ScrollViewProxy, animated: Bool = true, animation: Animation? = nil) {
        latestScrollGeneration += 1
        let generation = latestScrollGeneration
        isScrollingToLatest = true
        withAnimation(reduceMotion || !animated ? nil : animation ?? .easeOut(duration: 0.25)) {
            scrollToBottom(of: bottomAnchorID, with: proxy)
        } completion: {
            guard generation == latestScrollGeneration else { return }
            isScrollingToLatest = false
        }
    }

    /// Puts the row's bottom edge at the bottom of the view. Content that
    /// fits in the view stays at its top instead, where every row shows:
    /// SwiftUI takes it past its top by as much as its top inset when asked
    /// for a row at the bottom, and asks for that again as the insets change.
    private func scrollToBottom(of rowID: String, with proxy: ScrollViewProxy) {
        if restingPosition.contentFits {
            proxy.scrollTo(topAnchorID, anchor: .top)
        } else {
            proxy.scrollTo(rowID, anchor: .bottom)
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
            scrollToBottom(of: rowID, with: proxy)
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

/// The timeline's bottom inset, with whether its content fits in the view.
private struct InsetFitting: Equatable {
    let inset: CGFloat
    let fits: Bool
}
