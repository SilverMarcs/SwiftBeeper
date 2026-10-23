#if !os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct ChatDetailiOS: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var inputManager
    @State private var showingChatInfo = false
    @State private var isSearchPresented = false
    @FocusState private var isSearchFocused: Bool
    @State private var delegateProxy: AnyObject?
    @State private var firstUnreadID: String?
    @State private var profileSheetParticipant: ChatParticipant?
    @State private var composerHeight: CGFloat = 0
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
    @State private var timelineController = MobileTimelineController()


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

            let outgoingRows: [MobileTimelineRow] = outgoingTimelineEntries.map { entry in
                MobileTimelineRow(
                    content: .outgoing(entry.message, showsTimestamp: entry.showsTimestamp, linkedMessage: entry.linkedMessage),
                    chat: selectedChat,
                    isFocused: activeComposerMessageID == nil
                )
            }
            let messageRows: [MobileTimelineRow] = timelineEntries.map { entry in
                MobileTimelineRow(
                    content: .message(entry.message, showsTimestamp: entry.showsTimestamp, isFirstInGroup: entry.isFirstInGroup, isLastInGroup: entry.isLastInGroup, linkedMessage: entry.linkedMessage),
                    chat: selectedChat,
                    showsUnreadDivider: entry.message.id == firstUnreadID && outgoingMessages.isEmpty,
                    showsReadIndicator: entry.message.id == readIndicatorMessageID,
                    isFocused: activeComposerMessageID == nil || activeComposerMessageID == entry.message.id
                )
            }
            let loadingRows = chatStore.isLoadingOlderMessages
                ? [MobileTimelineRow(content: .loadingOlder, chat: selectedChat)] : []

            Group {
                ZStack {
                    MobileTimelineList(
                        rows: loadingRows + messageRows + outgoingRows,
                        controller: timelineController,
                        composerHeight: isIPad ? composerHeight : 0,
                        onLoadOlder: { loadOlderMessages(chatID: selectedChat.id) },
                        onTapLinkedMessage: { id in
                            scrollToLinkedMessage(id, chatID: selectedChat.id)
                        }
                    )
                    .ignoresSafeArea(.container, edges: .vertical)

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
                .background(.background)
                .onChange(of: chatStore.hasLoadedTimeline(for: selectedChat.id), initial: true) { _, loaded in
                    guard loaded else { return }
                    firstUnreadID = firstUnreadMessageID(messages: chatStore.messages(for: selectedChat.id), chat: selectedChat)
                }
                .onChange(of: MessageListTracker(
                    count: messages.count + outgoingMessages.count,
                    lastID: outgoingMessages.last?.timelineKey ?? messages.last?.id
                )) { oldTracker, newTracker in
                    // Scrolling belongs to the collection's committed snapshot.
                    // This callback only dismisses the unread marker.
                    guard oldTracker.lastID != nil, newTracker.lastID != oldTracker.lastID,
                          newTracker.count >= oldTracker.count else { return }
                    firstUnreadID = nil
                }
                .onChange(of: activeComposerMessageID) { _, newValue in
                    guard let newValue,
                          let target = chatStore.messages(for: selectedChat.id).first(where: { $0.id == newValue })
                    else { return }
                    timelineController.scrollToMessage(target.timelineKey)
                }
                .modifier(NavigationBarFocusVisibilityModifier(isFocusedOnComposerMessage: activeComposerMessageID != nil))
                .toolbar {
                    // iPad: avatar + name lives in the leading (navigation) slot.
                    // iPhone: stays centered in the title slot.
                    ToolbarItem(placement: isIPad ? .navigation : .principal) {
                        Button {
                            if selectedChat.isSingleChat, let other = selectedChat.otherParticipant {
                                profileSheetParticipant = other
                            } else {
                                showingChatInfo = true
                            }
                        } label: {
                            HStack {
                                ChatAvatarView(chat: selectedChat, dimension: 28)
                                Text(selectedChat.displayTitle)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: isIPhone ? 180 : nil)
                            }
                        }
                    }
                    // .sharedBackgroundVisibility(.hidden)

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
                .onDrop(of: [.item], isTargeted: nil) { providers in
                    inputManager.handleDrop(providers)
                }
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
                        .onChange(of: isSearchFocused) { _, focused in
                            guard focused, chatStore.activeComposerMessage == nil else { return }
                            timelineController.scrollToLatest(animated: true)
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
                .if(isIPad) {
                    // iPad: same inline composer as macOS.
                    $0.safeAreaBar(edge: .bottom, spacing: 0) {
                        MessageInputView()
                            .onGeometryChange(for: CGFloat.self) { geometry in
                                geometry.size.height
                            } action: { height in
                                composerHeight = height
                            }
                    }
                    .onChange(of: inputManager.isComposerFocused) { _, focused in
                        guard focused, chatStore.activeComposerMessage == nil else { return }
                        timelineController.scrollToLatest(animated: true)
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "Pick a Chat",
                systemImage: "list.bullet",
                description: Text("Select a chat from the sidebar to view messages.")
            )
        }
    }

    private func scrollToLinkedMessage(_ linkedID: String, chatID: String) {
        guard let target = chatStore.messages(for: chatID).first(where: { $0.id == linkedID }) else { return }
        timelineController.scrollToMessage(target.timelineKey)
    }

    private func loadOlderMessages(chatID: String) {
        guard chatStore.selectedChatID == chatID, chatStore.hasMoreMessages(for: chatID),
              !chatStore.isLoadingOlderMessages else { return }
        Task { @MainActor in
            // Older rows prepend; the collection layout preserves visible content.
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

private class TextFieldDelegateProxy: NSObject, UITextFieldDelegate {
    weak var originalDelegate: UITextFieldDelegate?
    var shouldReturn: ((UITextField) -> Bool)?

    init(originalDelegate: UITextFieldDelegate?) {
        self.originalDelegate = originalDelegate
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(textFieldShouldReturn(_:)) {
            return true
        }
        return originalDelegate?.responds(to: aSelector) ?? super.responds(to: aSelector)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        return originalDelegate
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if let shouldReturn = shouldReturn {
            return shouldReturn(textField)
        }
        return originalDelegate?.textFieldShouldReturn?(textField) ?? true
    }
}

private struct SearchIntrospector: UIViewRepresentable {
    var introspect: (UISearchTextField, UIView) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        Task { @MainActor in
            await Task.yield()
            if let searchField = findSearchTextField(startingFrom: view) {
                introspect(searchField, view)
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        Task { @MainActor in
            await Task.yield()
            if let searchField = findSearchTextField(startingFrom: uiView) {
                introspect(searchField, uiView)
            }
        }
    }

    private func findSearchTextField(startingFrom view: UIView) -> UISearchTextField? {
        var responder: UIResponder? = view
        while responder != nil {
            if let viewController = responder as? UIViewController {
                if let field = viewController.navigationItem.searchController?.searchBar.searchTextField {
                    return field
                }
                if let field = findSearchTextField(in: viewController.view) {
                    return field
                }
                if let navigationBar = viewController.navigationController?.navigationBar,
                   let field = findSearchTextField(in: navigationBar) {
                    return field
                }
            }
            responder = responder?.next
        }
        if let window = view.window, let field = findSearchTextField(in: window) {
            return field
        }
        return nil
    }

    private func findSearchTextField(in view: UIView) -> UISearchTextField? {
        if let searchField = view as? UISearchTextField {
            return searchField
        }
        for subview in view.subviews {
            if let field = findSearchTextField(in: subview) {
                return field
            }
        }
        return nil
    }
}
#endif
