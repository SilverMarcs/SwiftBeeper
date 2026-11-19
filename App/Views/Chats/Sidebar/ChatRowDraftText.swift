import SwiftUI

/// A chat row's preview of its unsent draft: a bold "Draft" label in place of
/// the sender's, an attachment symbol when the draft has attachments, then
/// the draft's text with Markdown removed.
struct ChatRowDraftText: View {
    let draft: ChatDraftPreview

    var body: some View {
        let label = Text("Draft: ").bold()
        let symbol = draft.symbol.map { Text("\(Image(systemName: $0)) ") } ?? Text(verbatim: "")
        Text("\(label)\(symbol)\(draft.text.previewAttributed)")
    }
}
