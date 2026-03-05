import SwiftUI

struct ChatDetailView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore
    private let bottomAnchorID = "bottom-id"

    var body: some View {
        if sessionStore.accessToken.isEmpty {
            TokenRequiredView(
                title: "No Chat Selected",
                systemImage: "bubble.left.and.bubble.right",
                description: "Add a token in Settings first."
            )
        } else if let selectedChat = chatStore.selectedChat {
            let messages = chatStore.messages(for: selectedChat.id)

            ScrollViewReader { proxy in
                List {
                    ForEach(messages) { message in
                        MessageRowView(
                            message: message,
                            chat: selectedChat
                        )
                        .id(message.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: -2, leading: 10, bottom: -2  , trailing: 10))
                    }
                    
                    Color.clear
                        .listRowInsets(.init())
                        .id(bottomAnchorID)
                }
                .task(id: selectedChat.id) {
                    chatStore.setReplyTo(nil)
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

    private func oneToOneParticipant(for chat: Chat) -> ChatParticipant? {
        guard chat.isSingleChat else { return nil }
        return chat.otherParticipant
    }
}
