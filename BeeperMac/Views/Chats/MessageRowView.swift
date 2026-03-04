import SwiftUI

struct MessageRowView: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(message.senderDisplayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Text(message.timestampText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(message.displayText)
                .font(.body)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    MessageRowView(message: Message(
        id: "msg-1",
        chatID: "chat-1",
        senderID: "@alice",
        senderName: "Alice",
        timestamp: .now,
        sortKey: "1",
        text: "Hello"
    ))
}
