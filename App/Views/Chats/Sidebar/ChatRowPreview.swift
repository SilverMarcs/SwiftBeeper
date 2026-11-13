import SwiftUI

/// A chat row's preview: who is typing while anyone is, otherwise the last
/// message. Both are text in the row's font within the same reserved lines,
/// so swapping them never changes the row's height.
///
/// Only this view reads the chat's typing, so a typing change re-renders this
/// preview alone, not the row or the list.
struct ChatRowPreview: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let chat: Chat

    var body: some View {
        let typingText = chatStore.chatListTyping.state(for: chat.id)
            .previewText(isSingleChat: chat.isSingleChat)
        // Overlaid rather than stacked, so a crossfade never lays both out
        // side by side.
        ZStack(alignment: .topLeading) {
            if let typingText {
                ChatRowTypingText(text: typingText, chat: chat)
                    .transition(.opacity)
            } else if let previewText = chat.previewText {
                ChatRowPreviewText(chat: chat, previewText: previewText)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: typingText)
    }
}
