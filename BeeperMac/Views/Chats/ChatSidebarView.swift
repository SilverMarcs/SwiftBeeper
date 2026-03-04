import SwiftUI

struct ChatSidebarView: View {
    let accessToken: String
    let chats: [Chat]
    let chatsError: String?
    let isLoadingChats: Bool
    @Binding var selectedChatID: String?

    var body: some View {
        Group {
            if accessToken.isEmpty {
                TokenRequiredView(
                    title: "Missing Token",
                    systemImage: "key.fill",
                    description: "Open Settings and add your Beeper bearer token."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoadingChats && chats.isEmpty {
                ProgressView("Loading chats...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let chatsError, chats.isEmpty {
                ContentUnavailableView(
                    "Could Not Load Chats",
                    systemImage: "exclamationmark.triangle",
                    description: Text(chatsError)
                )
            } else {
                List(selection: $selectedChatID) {
                    ForEach(chats) { chat in
                        ChatRowView(chat: chat)
                            .tag(chat.id)
                    }
                }
                .overlay(alignment: .bottom) {
                    if isLoadingChats {
                        ProgressView()
                            .padding(.bottom, 12)
                    }
                }
            }
        }
        .navigationTitle("Chats")
    }
}
