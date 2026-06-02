#if !os(macOS)
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - ChatDetailIos

struct ChatDetailIos: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(MessageStore.self) private var messageStore
    @Environment(RealtimeCoordinator.self) private var coordinator
    @State private var showingChatInfo = false
    @State private var isPreparingInitialScroll = false
    @State private var firstUnreadID: String?
    @State private var profileSheetParticipant: ChatParticipant?

    // iPhone Searchable Input View States
    @State private var searchText = ""
    @State private var isSearchActive = false
    @State private var draftsByChatID: [String: String] = [:]
    @State private var showingFilePicker = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []

    var body: some View {
        if sessionStore.accessToken.isEmpty {
            emptyTokenView
        } else if let selectedChat = chatStore.selectedChat {
            chatContent(for: selectedChat)
        } else {
            noChatSelectedView
        }
    }

    private var emptyTokenView: some View {
        TokenRequiredView(
            title: "No Chat Selected",
            systemImage: "bubble.left.and.bubble.right",
            description: "Add a token in Settings first."
        )
    }

    private var noChatSelectedView: some View {
        ContentUnavailableView("Pick a Chat", systemImage: "bubble.left.and.bubble.right",
                                description: Text("Select a chat from the sidebar."))
    }

    @ViewBuilder
    private func chatContent(for selectedChat: Chat) -> some View {
        let messages = messageStore.messages(for: selectedChat.id)
        let timelineEntries = timelineEntries(for: messages)
        let activeComposerMessageID = messageStore.activeComposerMessage?.id
        let readIndicatorMessageID = lastReadOutgoingMessageID(messages: messages, chat: selectedChat)

        let timeline = ChatTimelineView(
            selectedChat: selectedChat,
            messages: messages,
            timelineEntries: timelineEntries,
            activeComposerMessageID: activeComposerMessageID,
            readIndicatorMessageID: readIndicatorMessageID,
            firstUnreadID: $firstUnreadID,
            isPreparingInitialScroll: $isPreparingInitialScroll,
            showingChatInfo: $showingChatInfo,
            profileSheetParticipant: $profileSheetParticipant,
            onLinkTap: { linkedID in
                scrollToLinkedMessage(linkedID, chatID: selectedChat.id, messages: messages)
            }
        )

        if isIPhone {
            iPhoneChatView(timeline: timeline, selectedChat: selectedChat)
        } else {
            timeline
                .safeAreaBar(edge: .bottom, spacing: 0) { MessageInputView() }
        }
    }

    @ViewBuilder
    private func iPhoneChatView(timeline: ChatTimelineView, selectedChat: Chat) -> some View {
        timeline
            .searchable(text: $searchText, isPresented: $isSearchActive, prompt: "Message")
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .onSubmit(of: .search) { sendiPhoneMessage(chatID: selectedChat.id) }
                        .modifier(iPhoneBottomToolbarModifier(selectedChat: selectedChat, showingPhotoPicker: $showingPhotoPicker, showingFilePicker: $showingFilePicker))
            .fileImporter(isPresented: $showingFilePicker, allowedContentTypes: [.item]) { result in
                handleFileImport(result)
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItems,
                          matching: .any(of: [.images, .videos]))
            .onChange(of: selectedPhotoItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                Task { for item in newItems { await handlePhotoPick(item) } }
                selectedPhotoItems = []
            }
            .onChange(of: selectedChat.id) { oldID, newID in
                draftsByChatID[oldID] = searchText
                searchText = draftsByChatID[newID] ?? ""
            }
            .safeAreaBar(edge: .bottom, spacing: 0) { iPhoneBottomBar(selectedChat: selectedChat) }
    }

    // MARK: - iPhone compose

    private var isIPhone: Bool {
        UIDevice.current.userInterfaceIdiom == .phone
    }

    private func sendiPhoneMessage(chatID: String) {
        let text = searchText.trimmed
        guard !text.isEmpty else { return }
        searchText = ""
        Task {
            let ok = await messageStore.sendMessage(text: text, attachments: [], to: chatID)
            if ok { await coordinator.refreshAfterMessageMutation(chatID: chatID) }
        }
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        if case .success(let url) = result {
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { return }
            messageStore.pendingAttachments.append(PendingAttachment(
                fileData: data, fileName: url.lastPathComponent, mimeType: url.mimeType
            ))
        }
    }

    private func handlePhotoPick(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let mimeType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
        messageStore.pendingAttachments.append(PendingAttachment(
            fileData: data, fileName: "photo.\(ext)", mimeType: mimeType
        ))
    }

    // MARK: - Timeline helpers

    private func scrollToLinkedMessage(_ linkedID: String, chatID: String, messages: [Message]) {
        // Matches the old pattern; actual scrolling handled inside ChatTimelineView
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
            entries.append(TimelineEntry(message: message, showsTimestamp: showsTimestamp,
                                          isFirstInGroup: isFirstInGroup, isLastInGroup: isLastInGroup))
        }
        return entries
    }

    private func shouldShowTimestamp(before message: Message, previousMessage: Message?) -> Bool {
        guard let previousMessage else { return true }
        let calendar = Calendar.current
        if !calendar.isDate(message.timestamp, inSameDayAs: previousMessage.timestamp) { return true }
        return message.timestamp.timeIntervalSince(previousMessage.timestamp) >= 30 * 60
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
        return hasIncomingAfter ? nil : target.id
    }
}
private struct iPhoneBottomToolbarModifier: ViewModifier {
    @Environment(MessageStore.self) private var messageStore
    @Binding var showingPhotoPicker: Bool
    @Binding var showingFilePicker: Bool
    let selectedChat: Chat

    init(selectedChat: Chat, showingPhotoPicker: Binding<Bool>, showingFilePicker: Binding<Bool>) {
        self.selectedChat = selectedChat
        _showingPhotoPicker = showingPhotoPicker
        _showingFilePicker = showingFilePicker
    }

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .bottomBar) {
                Menu {
                    Button { showingPhotoPicker = true } label: {
                        Label("Photos Library", systemImage: "photo.on.rectangle.angled")
                    }
                    Button { showingFilePicker = true } label: {
                        Label("Attach Files", systemImage: "paperclip")
                    }
                } label: { Image(systemName: "plus") }
            }
            ToolbarSpacer(.fixed, placement: .bottomBar)
            DefaultToolbarItem(kind: .search, placement: .bottomBar)
            ToolbarSpacer(.fixed, placement: .bottomBar)
        }
    }
}

private struct iPhoneBottomBar: View {
    let selectedChat: Chat
    @Environment(MessageStore.self) private var messageStore

    var body: some View {
        if selectedChat.cannotMessage == true {
            Text("You can't message this person")
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: .infinity).glassEffect()
                .padding(.horizontal).padding(.vertical, 10)
        } else {
            // HStack(spacing: 8) {
                // Spacer()
                if !messageStore.pendingAttachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(messageStore.pendingAttachments) { pending in
                                PendingAttachmentPreview(pending: pending, isSending: messageStore.isSendingMessage,
                                                          onRemove: { messageStore.removePendingAttachment(id: pending.id) })
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            // }
            // .glasdsEffect()
        }
    }
}

// MARK: - ChatTimelineView

private struct ChatTimelineView: View {
    let selectedChat: Chat
    let messages: [Message]
    let timelineEntries: [TimelineEntry]
    let activeComposerMessageID: String?
    let readIndicatorMessageID: String?
    @Binding var firstUnreadID: String?
    @Binding var isPreparingInitialScroll: Bool
    @Binding var showingChatInfo: Bool
    @Binding var profileSheetParticipant: ChatParticipant?
    var onLinkTap: (String) -> Void

    @Environment(MessageStore.self) private var messageStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(RealtimeCoordinator.self) private var coordinator

    private let bottomAnchorID = "bottom-id"

    var body: some View {
        ScrollViewReader { proxy in
            timelineList(proxy: proxy)
                .task(id: selectedChat.id) { await loadChat(proxy: proxy) }
                .onChange(of: MessageListTracker(count: messages.count, lastID: messages.last?.id)) { old, new in
                    handleMessageCountChange(old: old, new: new, proxy: proxy)
                }
                .onChange(of: activeComposerMessageID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(newValue, anchor: .center) }
                }
                .listStyle(.plain)
                .animation(.default, value: activeComposerMessageID)
                .navigationTitle(selectedChat.displayTitle)
                .modifier(NavigationBarFocusVisibilityModifier(isFocusedOnComposerMessage: activeComposerMessageID != nil))
                .modifier(TimelineToolbarModifier(selectedChat: selectedChat, showingChatInfo: $showingChatInfo, profileSheetParticipant: $profileSheetParticipant))
                .onDrop(of: [.item], isTargeted: nil) { providers in handleDrop(providers) }
        }
    }

    private func timelineList(proxy: ScrollViewProxy) -> some View {
        List {
            if messageStore.hasMoreMessages(for: selectedChat.id) {
                loadMoreSpinner
                    .onAppear {
                        guard !messageStore.isLoadingOlderMessages else { return }
                        loadOlderMessages(chatID: selectedChat.id, proxy: proxy)
                    }
            }
            ForEach(timelineEntries) { entry in
                timelineEntryView(entry)
            }
            Color.clear
                .modifier(TimelineFocusEffect(isFocused: activeComposerMessageID == nil))
                .listRowInsets(.init())
                .listRowSeparator(.hidden)
                .id(bottomAnchorID)
        }
    }

    private var loadMoreSpinner: some View {
        ProgressView()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
    }

    @ViewBuilder
    private func timelineEntryView(_ entry: TimelineEntry) -> some View {
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
            onTapLinkedMessage: onLinkTap
        )
        .modifier(TimelineFocusEffect(
            isFocused: activeComposerMessageID == nil || activeComposerMessageID == entry.message.id
        ))
        .id(entry.message.id)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
    }

    private func loadChat(proxy: ScrollViewProxy) async {
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

    private func scrollToBottom(with proxy: ScrollViewProxy, animated: Bool) {
        if animated { withAnimation { proxy.scrollTo(bottomAnchorID, anchor: .bottom) } }
        else { proxy.scrollTo(bottomAnchorID, anchor: .bottom) }
    }

    private func firstUnreadMessageID(messages: [Message], chat: Chat) -> String? {
        guard chat.unreadCount > 0 else { return nil }
        if let lastReadSortKey = chat.lastReadMessageSortKey {
            let lastReadNumeric = Int64(lastReadSortKey) ?? 0
            return messages.first(where: { $0.numericSortKey > lastReadNumeric })?.id
        }
        return messages.first(where: { $0.isUnread == true })?.id
    }

    private func handleMessageCountChange(old: MessageListTracker, new: MessageListTracker, proxy: ScrollViewProxy) {
        guard !isPreparingInitialScroll else { return }
        guard new.count > old.count else { return }
        guard new.lastID != old.lastID else { return }
        firstUnreadID = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            scrollToBottom(with: proxy, animated: true)
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

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        for provider in providers {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, _ in
                guard let url else { return }
                guard let data = try? Data(contentsOf: url) else { return }
                Task { @MainActor in
                    messageStore.pendingAttachments.append(PendingAttachment(
                        fileData: data, fileName: url.lastPathComponent, mimeType: url.mimeType
                    ))
                }
            }
        }
        return true
    }
}

// MARK: - Toolbar modifier

private struct TimelineToolbarModifier: ViewModifier {
    let selectedChat: Chat
    @Binding var showingChatInfo: Bool
    @Binding var profileSheetParticipant: ChatParticipant?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .title) {
                    navigationAvatar
                }
//                .sharedBackgroundVisibility(.hidden)
                
                ToolbarItem(placement: .primaryAction) {
                    Button { showingChatInfo = true } label: {
                        Label("Chat Info", systemImage: "info")
                    }
                }
            }
            .sheet(isPresented: $showingChatInfo) { ChatInfoSheet(chat: selectedChat) }
            .sheet(item: $profileSheetParticipant) { participant in
                ParticipantProfileSheet(participant: participant)
            }
    }

    @ViewBuilder
    private var navigationAvatar: some View {
        if selectedChat.isSingleChat, let other = selectedChat.otherParticipant {
            Button { profileSheetParticipant = other } label: {
                HStack {
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
                Text(selectedChat.displayTitle)
                }
            }
            .buttonStyle(.plain)
        } else {
            ChatAvatarView(chat: selectedChat, dimension: 28)
        }
    }
}

// MARK: - Supporting types

private struct TimelineEntry: Identifiable {
    let message: Message
    let showsTimestamp: Bool
    let isFirstInGroup: Bool
    let isLastInGroup: Bool
    var id: String { message.timelineKey }
}

private struct MessageListTracker: Equatable {
    let count: Int
    let lastID: String?
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

private struct UnreadDividerView: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(.background.quinary).frame(height: 1)
            Text("New Messages").font(.caption).bold().foregroundStyle(.secondary)
            Rectangle().fill(.background.quinary).frame(height: 1)
        }
        .padding(.vertical, 4)
    }
}

private struct TimestampDividerView: View {
    let timestamp: Date
    var body: some View {
        Text(displayText).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
    }
    private var displayText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(timestamp) { return timestamp.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(timestamp) { return "Yesterday at \(timestamp.formatted(date: .omitted, time: .shortened))" }
        return timestamp.formatted(date: .abbreviated, time: .shortened)
    }
}
#endif
