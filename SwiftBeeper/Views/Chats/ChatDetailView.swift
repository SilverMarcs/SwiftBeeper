import SwiftUI
import UniformTypeIdentifiers

struct ChatDetailView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(MessageStore.self) private var messageStore
    @Environment(RealtimeCoordinator.self) private var coordinator
    @State private var showingChatInfo = false
    @State private var isPreparingInitialScroll = false
    private let bottomAnchorID = "bottom-id"

    var body: some View {
        if sessionStore.accessToken.isEmpty {
            TokenRequiredView(
                title: "No Chat Selected",
                systemImage: "bubble.left.and.bubble.right",
                description: "Add a token in Settings first."
            )
        } else if let selectedChat = chatStore.selectedChat {
            let messages = messageStore.messages(for: selectedChat.id)
            let timelineEntries = timelineEntries(for: messages)
            let activeComposerMessageID = messageStore.activeComposerMessage?.id

            ScrollViewReader { proxy in
                let firstUnreadID = firstUnreadMessageID(messages: messages, chat: selectedChat)

                List {
                    LoadOlderMessagesButton(
                        isLoading: messageStore.isLoadingOlderMessages,
                        canLoadMore: messageStore.hasMoreMessages(for: selectedChat.id),
                        action: {
                            loadOlderMessages(chatID: selectedChat.id)
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))

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
                            chat: selectedChat
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
                                    messageStore.setReplyTo(entry.message)
                                }
                            }
                            .tint(.accentColor)
                            .labelStyle(.iconOnly)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if messageStore.canEdit(entry.message, in: selectedChat) {
                                Button("Edit", systemImage: "pencil") {
                                    withAnimation {
                                        messageStore.startEditing(entry.message, in: selectedChat)
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
                    resetScrollPaginationState()
                    coordinator.setSelectedChatID(selectedChat.id)
                    messageStore.setReplyTo(nil)
                    messageStore.cancelEditing()
                    async let detail: () = chatStore.loadChatDetail(for: selectedChat.id)
                    async let messagesLoad: () = messageStore.loadMessages(for: selectedChat.id)
                    await messagesLoad
                    try? await Task.sleep(for: .milliseconds(50))
                    scrollToBottom(with: proxy, animated: false)
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                    isPreparingInitialScroll = false
                    await detail
                }
                .onChange(of: MessageListTracker(count: messages.count, lastID: messages.last?.id)) { oldTracker, newTracker in
                    guard !isPreparingInitialScroll else { return }
                    guard newTracker.count > oldTracker.count else { return }
                    guard newTracker.lastID != oldTracker.lastID else { return }

                    Task { @MainActor in
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
                        ChatAvatarView(chat: selectedChat, dimension: 28)
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
                    handleDrop(providers)
                }
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    MessageInputView()
                }
            }
//            .id(selectedChat.id)
        } else {
            ContentUnavailableView(
                "Pick a Chat",
                systemImage: "list.bullet",
                description: Text("Select a chat from the sidebar to view messages.")
            )
            .task {
                coordinator.setSelectedChatID(nil)
                isPreparingInitialScroll = false
                resetScrollPaginationState()
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, _ in
            guard let url else { return }
            guard let data = try? Data(contentsOf: url) else { return }
            let fileName = url.lastPathComponent
            let mimeType: String = {
                if let utType = UTType(filenameExtension: url.pathExtension) {
                    return utType.preferredMIMEType ?? "application/octet-stream"
                }
                return "application/octet-stream"
            }()

            Task { @MainActor in
                messageStore.pendingAttachment = PendingAttachment(
                    fileData: data,
                    fileName: fileName,
                    mimeType: mimeType
                )
            }
        }

        return true
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

    private func loadOlderMessages(chatID: String) {
        Task { @MainActor in
            _ = await messageStore.loadOlderMessages(for: chatID)
        }
    }

    private func resetScrollPaginationState() {
    }

    private func firstUnreadMessageID(messages: [Message], chat: Chat) -> String? {
        guard chat.unreadCount > 0 else { return nil }

        if let lastReadSortKey = chat.lastReadMessageSortKey {
            return messages.first(where: { $0.sortKey > lastReadSortKey })?.id
        }

        return messages.first(where: { $0.isUnread == true })?.id
    }

    private func timelineEntries(for messages: [Message]) -> [TimelineEntry] {
        var previousMessage: Message?

        return messages.map { message in
            let showsTimestamp = shouldShowTimestamp(before: message, previousMessage: previousMessage)
            previousMessage = message
            return TimelineEntry(message: message, showsTimestamp: showsTimestamp)
        }
    }

    private func shouldShowTimestamp(before message: Message, previousMessage: Message?) -> Bool {
        guard let previousMessage else { return true }

        let calendar = Calendar.current
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

private struct TimelineFocusEffect: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isFocused ? 1 : 0.35)
            .blur(radius: isFocused ? 0 : 4)
            .scaleEffect(isFocused ? 1 : 0.992)
            .allowsHitTesting(isFocused)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

private struct LoadOlderMessagesButton: View {
    let isLoading: Bool
    let canLoadMore: Bool
    let action: () -> Void

    var body: some View {
        if canLoadMore || isLoading {
            Button {
                action()
            } label: {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Load older messages")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.link)
            .disabled(isLoading)
        }
    }
}

private struct NavigationBarFocusVisibilityModifier: ViewModifier {
    let isFocusedOnComposerMessage: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        content.toolbarVisibility(isFocusedOnComposerMessage ? .hidden : .visible, for: .navigationBar)
        #else
        content
        #endif
    }
}

private struct MessageListTracker: Equatable {
    let count: Int
    let lastID: String?
}

private struct TimelineEntry: Identifiable {
    let message: Message
    let showsTimestamp: Bool

    var id: String { message.timelineKey }
}

private struct UnreadDividerView: View {
    var body: some View {
        HStack(spacing: 8) {
            line
            Text("New Messages")
                .font(.caption)
                .bold()
                .foregroundStyle(.secondary)
            line
        }
        .padding(.vertical, 4)
    }

    private var line: some View {
        Rectangle()
            .fill(.background.quinary)
            .frame(height: 1)
    }
}

private struct TimestampDividerView: View {
    let timestamp: Date

    var body: some View {
        Text(displayText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }

    private var displayText: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(timestamp) {
            return timestamp.formatted(date: .omitted, time: .shortened)
        }

        if calendar.isDateInYesterday(timestamp) {
            return "Yesterday at \(timestamp.formatted(date: .omitted, time: .shortened))"
        }

        return timestamp.formatted(date: .abbreviated, time: .shortened)
    }
}
