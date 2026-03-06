import SwiftUI

struct ChatDetailView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    @Environment(MessageStore.self) private var messageStore
    @State private var showingChatInfo = false
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

            ScrollViewReader { proxy in
                let firstUnreadID = firstUnreadMessageID(messages: messages, chat: selectedChat)

                List {
                    ForEach(messages) { message in
                        if message.id == firstUnreadID {
                            UnreadDividerView()
                                .transition(.opacity)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                        }

                        MessageRowView(
                            message: message,
                            chat: selectedChat
                        )
                        .id(message.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2  , trailing: 10))
                    }

                    Color.clear
                        .listRowInsets(.init())
                        .id(bottomAnchorID)
                }
                .animation(.default, value: firstUnreadID)
                .task(id: selectedChat.id) {
                    messageStore.setReplyTo(nil)
                    async let detail: () = chatStore.loadChatDetail(for: selectedChat.id)
                    await Task.yield()
                    scrollToBottom(with: proxy, animated: false)
                    await detail
                }
                .onChange(of: messages.count) {
                    scrollToBottom(with: proxy, animated: true)
                }
                .listStyle(.plain)
                .safeAreaBar(edge: .bottom, spacing: 0) {
                    MessageInputView()
                }
                .navigationTitle(selectedChat.displayTitle)
                .toolbar {
                    if let otherParticipant = oneToOneParticipant(for: selectedChat) {
                        ToolbarItem(placement: .navigation) {
                            ProfileAvatarView(
                                name: otherParticipant.displayName,
                                imageURLString: otherParticipant.imgURL,
                                dimension: 28
                            )
                            .accessibilityLabel("\(otherParticipant.displayName) avatar")
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }

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
            }
        } else {
            ContentUnavailableView(
                "Pick a Chat",
                systemImage: "list.bullet",
                description: Text("Select a chat from the sidebar to view messages.")
            )
        }
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

    private func firstUnreadMessageID(messages: [Message], chat: Chat) -> String? {
        guard chat.unreadCount > 0 else { return nil }

        if let lastReadSortKey = chat.lastReadMessageSortKey {
            return messages.first(where: { $0.sortKey > lastReadSortKey })?.id
        }

        return messages.first(where: { $0.isUnread == true })?.id
    }

    private func oneToOneParticipant(for chat: Chat) -> ChatParticipant? {
        guard chat.isSingleChat else { return nil }
        return chat.otherParticipant
    }
}

private struct UnreadDividerView: View {
    var body: some View {
        HStack(spacing: 8) {
            line
            Text("New Messages")
                .font(.caption)
                .fontWeight(.semibold)
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
