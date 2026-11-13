import SwiftUI

/// A link's preview inside its message's bubble: the page's image, title,
/// description and domain. Tapping it opens the link.
struct MessageLinkPreviewCard: View {
    let preview: MessageLinkPreview
    let isOutgoing: Bool
    @Environment(\.openURL) private var openURL

    private static let cornerRadius: CGFloat = 10

    var body: some View {
        Button {
            if let url = URL(string: preview.url) { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let imageURL = preview.imageURL {
                    MessageLinkPreviewImage(source: imageURL, aspectRatio: preview.imageAspectRatio)
                }
                MessageLinkPreviewText(preview: preview)
            }
            // Secondary text derives from this: white on the accent fill.
            .foregroundStyle(isOutgoing ? .white : .primary)
            .background(isOutgoing ? AnyShapeStyle(.white.quinary) : AnyShapeStyle(.quinary))
            .clipShape(.rect(cornerRadius: Self.cornerRadius))
            .contentShape(.rect(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(.plain)
        .help(preview.url)
        .accessibilityHint("Opens \(preview.domain)")
    }
}
