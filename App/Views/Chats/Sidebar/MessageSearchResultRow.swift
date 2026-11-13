import SwiftUI

/// A message matching the chat list's search: its chat's avatar and name,
/// when it was sent, and its text around the match, after the sender's name
/// in groups.
struct MessageSearchResultRow: View {
    let message: Message
    let chat: Chat?
    let query: String

    var body: some View {
        HStack(spacing: 8) {
            if let chat {
                #if os(macOS)
                ChatAvatarView(chat: chat, dimension: 43)
                #else
                ChatAvatarView(chat: chat, dimension: 48)
                #endif
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat?.displayTitle ?? message.senderDisplayName)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    Text(message.timestamp.chatListText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(senderPrefix + MessageSearchSnippet.text(resultText, query: query))
                    #if os(iOS)
                    .font(.callout)
                    #endif
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
        }
        #if os(macOS)
        .padding(5)
        #else
        .padding(-1)
        #endif
        .contentShape(.rect)
    }

    /// "You: " for your messages, and the sender's first name in groups.
    /// A sender known only by Matrix ID, such as one who left, gets none.
    private var senderPrefix: AttributedString {
        if message.isSender { return AttributedString(String(localized: "You: ")) }
        guard chat?.isGroupChat == true, !message.senderDisplayName.hasPrefix("@"),
              let firstName = message.senderDisplayName.split(whereSeparator: \.isWhitespace).first else { return "" }
        return AttributedString("\(firstName): ")
    }

    /// The text that matched: the message's, or its file's name.
    private var resultText: String {
        message.visibleText ?? message.attachments?.first?.fileName ?? message.displayText
    }
}
