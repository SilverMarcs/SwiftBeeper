import SwiftUI

/// A compact typing bubble in place of a chat row's preview, after a bold
/// label of who is typing in a group chat. It sits on the first of the
/// preview's reserved lines, like preview text, so the row keeps its height.
struct ChatRowTypingIndicator: View {
    let typing: ChatTypingState
    let chat: Chat

    var body: some View {
        // Holds the preview's reserved lines while no preview text is shown.
        Text(verbatim: " ")
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                HStack {
                    if chat.isGroupChat, let typistsLabel = typing.typistsLabel {
                        // Styled like the last message's sender label.
                        Text("\(typistsLabel):")
                            .bold()
                            // One line beside the bubble, not the preview's two.
                            .lineLimit(1, reservesSpace: false)
                    }

                    ChatRowTypingBubble()
                        // The row dims its preview text; the dots match the timeline's.
                        .foregroundStyle(.primary)
                        // A long label truncates before the bubble shrinks.
                        .fixedSize()
                }
            }
            .accessibilityElement(children: .ignore)
            // A one-to-one chat's "typing…" doesn't say who on its own.
            .accessibilityLabel(chat.isSingleChat
                ? Text("\(chat.displayTitle) is typing")
                : Text(typing.previewText(isSingleChat: false) ?? ""))
    }
}
