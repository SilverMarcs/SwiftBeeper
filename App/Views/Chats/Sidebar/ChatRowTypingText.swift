import SwiftUI

/// "typing…" or who is typing, in place of a chat row's preview. It's tinted
/// like an unread badge, except on a selected row, where the selection's
/// own text colour keeps it legible.
struct ChatRowTypingText: View {
    @Environment(\.backgroundProminence) private var backgroundProminence
    let text: String
    let chat: Chat

    var body: some View {
        Text(text)
            .foregroundStyle(backgroundProminence == .increased ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
            // A one-to-one chat's "typing…" doesn't say who on its own.
            .accessibilityLabel(chat.isSingleChat ? Text("\(chat.displayTitle) is typing") : Text(text))
    }
}
