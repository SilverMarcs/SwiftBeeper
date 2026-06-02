#if os(macOS)
import SwiftUI
import UniformTypeIdentifiers

struct ChatDetailMac: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(MessageStore.self) private var messageStore
    @Environment(RealtimeCoordinator.self) private var coordinator
    @State private var showingChatInfo = false
    @State private var isPreparingInitialScroll = false
    @State private var firstUnreadID: String?
    @State private var profileSheetParticipant: ChatParticipant?
    private let bottomAnchorID = "bottom-id"

    @ViewBuilder
    private func makeMainContent(
        selectedChat: Chat,
        messages: [Message],
        timelineEntries: [TimelineEntry],
        activeComposerMessageID: String?,
        readIndicatorMessageID: String?
    ) -> some View {
        ScrollViewReader { proxy in
            List {
                if messageStore.hasMoreMessages(for: selectedChat.id) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
                        .onAppear {
                            guard !messageStore.isLoadingOlderMessages else { return }
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
                                messageStore.setReplyTo(entry.message)
                            }
                        }
                        .tint(.accentColor)
                        .labelStyle(.iconOnly)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if !entry.message.isEmptyDeleted && entry.message.isOutgoing(in: selectedChat) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task {
                                    await messageStore.deleteMessage(entry.message.id, in: selectedChat.id)
                                }
                            }
                            .labelStyle(.iconOnly)
                        }

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
                defer { isPreparingInitialScroll = false }
                firstUnreadID = nil
                coordinator.setSelectedChatID(selectedChat.id)
                messageStore.setReplyTo(nil)
                messageStore.cancelEditing()
                async let detail: () = chatStore.loadChatDetail(for: selectedChat.id)
                async let messagesLoad = messageStore.loadMessages(for: selectedChat.id)
                let _ = await messagesLoad
                firstUnreadID = firstUnreadMessageID(messages: messageStore.messages(for: selectedChat.id), chat: selectedChat)
                try? await Task.sleep(for: .milliseconds(50))
                scrollToBottom(with: proxy, animated: false)
                try? await Task.sleep(for: .milliseconds(100))
                await detail
            }
            .onChange(of: MessageListTracker(count: messages.count, lastID: messages.last?.id)) { oldTracker, newTracker in
                guard !isPreparingInitialScroll else { return }
                guard newTracker.count > oldTracker.count else { return }
                guard newTracker.lastID != oldTracker.lastID else { return }

                firstUnreadID = nil
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
            .onDrop(of: [.item], isTargeted: nil) { providers in
                handleDrop(providers)
            }
        }
    }

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
            let readIndicatorMessageID = lastReadOutgoingMessageID(messages: messages, chat: selectedChat)

            makeMainContent(
                selectedChat: selectedChat,
                messages: messages,
                timelineEntries: timelineEntries,
                activeComposerMessageID: activeComposerMessageID,
                readIndicatorMessageID: readIndicatorMessageID
            )
            .safeAreaBar(edge: .bottom, spacing: 0) {
                MessageInputView()
            }
        } else {
            ContentUnavailableView(
                "Pick a Chat",
                systemImage: "list.bullet",
                description: Text("Select a chat from the sidebar to view messages.")
            )
            .task {
                coordinator.setSelectedChatID(nil)
                isPreparingInitialScroll = false
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }

        for provider in providers {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, _ in
                guard let url else { return }
                guard let data = try? Data(contentsOf: url) else { return }
                let fileName = url.lastPathComponent
                let mimeType = url.mimeType

                Task { @MainActor in
                    messageStore.pendingAttachments.append(PendingAttachment(
                        fileData: data,
                        fileName: fileName,
                        mimeType: mimeType
                    ))
                }
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

    private func scrollToLinkedMessage(_ linkedID: String, chatID: String, proxy: ScrollViewProxy) {
        let messages = messageStore.messages(for: chatID)
        guard let target = messages.first(where: { $0.id == linkedID }) else { return }

        withAnimation(.easeInOut(duration: 0.3)) {
            proxy.scrollTo(target.timelineKey, anchor: .center)
        }
    }

    private func loadOlderMessages(chatID: String, proxy: ScrollViewProxy) {
        let anchorMessageID = messageStore.messages(for: chatID).first?.timelineKey
        Task { @MainActor in
            _ = await messageStore.loadOlderMessages(for: chatID)
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

    private func lastReadOutgoingMessageID(messages: [Message], chat: Chat) -> String? {
        var lastReadOutgoing: Message?
        for message in messages {
            guard message.isOutgoing(in: chat) else { continue }
            guard messageStore.isReadByOther(message: message) else { continue }
            lastReadOutgoing = message
        }
        guard let target = lastReadOutgoing else { return nil }

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

        for i in 0..<count {
            let message = messages[i]
            let prev: Message? = i > 0 ? messages[i - 1] : nil
            let next: Message? = i < count - 1 ? messages[i + 1] : nil

            let showsTimestamp = shouldShowTimestamp(before: message, previousMessage: prev)

            let sameSenderAsPrev = prev.map { $0.senderID == message.senderID } ?? false
            let sameSenderAsNext = next.map { $0.senderID == message.senderID } ?? false

            let nextShowsTimestamp = next.map { shouldShowTimestamp(before: $0, previousMessage: message) } ?? false
            let nextIsUnread = next.map { $0.id == firstUnreadID } ?? false

            let isFirstInGroup = !sameSenderAsPrev || showsTimestamp || message.id == firstUnreadID
            let isLastInGroup = !sameSenderAsNext || nextShowsTimestamp || nextIsUnread

            entries.append(TimelineEntry(message: message, showsTimestamp: showsTimestamp, isFirstInGroup: isFirstInGroup, isLastInGroup: isLastInGroup))
        }

        return entries
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
    let isFirstInGroup: Bool
    let isLastInGroup: Bool

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
#endif
