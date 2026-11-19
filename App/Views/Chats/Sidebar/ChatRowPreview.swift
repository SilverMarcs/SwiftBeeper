import SwiftUI

/// A chat row's preview: a compact typing bubble while anyone is typing,
/// then the unsent draft of a chat that isn't open, otherwise the last
/// message. All keep the same reserved lines of the row's font, so swapping
/// them never changes the row's height.
///
/// Only this view reads the chat's typing, so a typing change re-renders this
/// preview alone, not the row or the list.
struct ChatRowPreview: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var inputManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let chat: Chat

    var body: some View {
        let typing = chatStore.chatListTyping.state(for: chat.id)
        let typingText = typing.previewText(isSingleChat: chat.isSingleChat)
        // The open chat shows its draft in the composer, and skipping it
        // keeps each keystroke there from re-rendering this row.
        let draft = chatStore.selectedChatID == chat.id ? nil : inputManager.draftPreview(forChatID: chat.id)
        // Overlaid rather than stacked, so a crossfade never lays both out
        // side by side.
        ZStack(alignment: .topLeading) {
            if let typingText {
                ChatRowTypingIndicator(typing: typing, chat: chat)
                    .transition(.opacity)
            } else if let draft {
                ChatRowDraftText(draft: draft)
                    .transition(.opacity)
            } else if let previewText = chat.previewText {
                ChatRowPreviewText(chat: chat, previewText: previewText)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: typingText)
    }
}
