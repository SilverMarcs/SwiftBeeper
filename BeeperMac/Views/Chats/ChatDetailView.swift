import SwiftUI

struct ChatDetailView: View {
    let accessToken: String
    let selectedChat: Chat?
    let messages: [Message]
    let isLoadingMessages: Bool
    let messagesError: String?

    var body: some View {
        if accessToken.isEmpty {
            TokenRequiredView(
                title: "No Chat Selected",
                systemImage: "bubble.left.and.bubble.right",
                description: "Add a token in Settings first."
            )
        } else if let selectedChat {
            List(messages) { message in
                MessageRowView(message: message)
            }
            .overlay {
                if isLoadingMessages {
                    ProgressView("Loading messages...")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let messagesError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(messagesError)
                            .lineLimit(2)
                    }
                    .font(.footnote)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.red.opacity(0.12))
                }
            }
            .navigationTitle(selectedChat.displayTitle)
        } else {
            ContentUnavailableView(
                "Pick a Chat",
                systemImage: "list.bullet",
                description: Text("Select a chat from the sidebar to view messages.")
            )
        }
    }
}
