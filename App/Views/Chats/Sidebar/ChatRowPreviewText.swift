import SwiftUI

/// A chat row's last-message preview: a bold sender label, an attachment
/// symbol when the message carries media or files, then the caption or an
/// attachment summary such as "Photo" or "Audio · 0:12".
struct ChatRowPreviewText: View {
    let chat: Chat
    let previewText: String

    var body: some View {
        // A thread reply that notified you previews with a thread arrow.
        let thread = chat.preview?.isHiddenThreadReply == true
            ? Text("\(Image(systemName: "arrow.turn.down.right")) ") : Text(verbatim: "")
        let sender = Text(chat.previewSenderPrefix).bold()
        let symbol = chat.previewSymbol.map { Text("\(Image(systemName: $0)) ") } ?? Text(verbatim: "")
        Text("\(thread)\(sender)\(symbol)\(previewText.previewAttributed)")
    }
}
