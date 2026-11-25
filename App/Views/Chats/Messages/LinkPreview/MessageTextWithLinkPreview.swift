import SwiftUI

/// A text bubble's contents: the message's text and, below it, a card for
/// its first previewable link. A bridge's preview shows at once; otherwise
/// the homeserver's is fetched while the row is shown, and the card appears
/// only once it arrives. Messages without links lay out their text alone.
struct MessageTextWithLinkPreview: View {
    let message: Message
    let text: String
    let isOutgoing: Bool

    /// Off for now: every message lays out its text alone and nothing is
    /// fetched. The core still maps bridge previews, so turning this back on
    /// is the only change needed.
    static let isEnabled = false

    var body: some View {
        if !Self.isEnabled || (message.linkPreview == nil && message.linkPreviewURL == nil) {
            MessageTextView(text: text, isOutgoing: isOutgoing, expansionID: message.id, isRoomMention: message.isRoomMention == true)
        } else {
            MessageLinkPreviewLayout {
                MessageTextView(text: text, isOutgoing: isOutgoing, expansionID: message.id, isRoomMention: message.isRoomMention == true)
                if let preview = message.linkPreview {
                    MessageLinkPreviewCard(preview: preview, isOutgoing: isOutgoing)
                } else if let url = message.linkPreviewURL {
                    FetchedLinkPreviewCard(url: url, isOutgoing: isOutgoing)
                }
            }
        }
    }
}
