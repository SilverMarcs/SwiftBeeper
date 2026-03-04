import SwiftUI

struct ChatRowView: View {
    let chat: Chat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(chat.displayTitle)
                .font(.headline)

            if let previewText = chat.previewText {
                Text(previewText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    ChatRowView(chat: Chat(
        id: "chat-1",
        title: "General",
        unreadCount: 0,
        preview: nil
    ))
}
