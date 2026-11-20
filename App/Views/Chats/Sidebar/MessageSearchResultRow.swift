import SwiftUI

/// A message matching the chat list's search, laid out like a chat row: its
/// chat's avatar and name, when it was sent, and its text around the match
/// with the match highlighted, after a bold sender label as in chat previews.
struct MessageSearchResultRow: View {
    let message: Message
    let chat: Chat?
    /// The logo badging the avatar; nil shows the plain avatar.
    let networkImageURL: String?
    let query: String

    var body: some View {
        ChatRowLayout(
            chat: chat,
            networkImageURL: networkImageURL,
            title: chat?.displayTitle ?? message.senderDisplayName,
            timeText: message.timestamp.chatListText
        ) {
            let sender = Text(senderPrefix).bold()
            let snippet = Text(MessageSearchSnippet.text(resultText, query: query))
            Text("\(sender)\(snippet)")
        } badges: {}
        .contentShape(.rect)
    }

    /// "You: " for your messages, and the sender's first name in groups.
    /// A sender known only by Matrix ID, such as one who left, gets none.
    private var senderPrefix: String {
        if message.isSender { return String(localized: "You: ") }
        guard chat?.isGroupChat == true, !message.senderDisplayName.hasPrefix("@"),
              let firstName = message.senderDisplayName.split(whereSeparator: \.isWhitespace).first else { return "" }
        return "\(firstName): "
    }

    /// The text that matched: the message's, or its file's name.
    private var resultText: String {
        message.visibleText ?? message.attachments?.first?.fileName ?? message.displayText
    }
}
