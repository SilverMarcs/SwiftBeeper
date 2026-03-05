import SwiftUI

struct ChatSidebarView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ChatStore.self) private var chatStore

    var body: some View {
        @Bindable var chatStore = chatStore

        Group {
            if sessionStore.accessToken.isEmpty {
                TokenRequiredView(
                    title: "Missing Token",
                    systemImage: "key.fill",
                    description: "Open Settings and add your Beeper bearer token."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if chatStore.isLoadingChats && chatStore.chats.isEmpty {
                ProgressView("Loading chats...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let chatsError = chatStore.chatsError, chatStore.chats.isEmpty {
                ContentUnavailableView(
                    "Could Not Load Chats",
                    systemImage: "exclamationmark.triangle",
                    description: Text(chatsError)
                )
            } else {
                List(selection: $chatStore.selectedChatID) {
                    ForEach(chatStore.chats) { chat in
                        ChatRowView(chat: chat)
                            .tag(chat.id)
                    }
                }
                .overlay(alignment: .bottom) {
                    if chatStore.isLoadingChats {
                        ProgressView()
                            .padding(.bottom, 12)
                    }
                }
            }
        }
        .navigationTitle("Chats")
    }
}
