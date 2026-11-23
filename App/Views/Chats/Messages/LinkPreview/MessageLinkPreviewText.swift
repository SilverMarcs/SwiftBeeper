import SwiftUI

/// A link preview's title, description and domain, in the card's
/// foreground style.
struct MessageLinkPreviewText: View {
    let preview: MessageLinkPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let title = preview.title {
                Text(title)
                    .chatFont(.subheadline)
                    .bold()
                    .lineLimit(2)
            }
            if let description = preview.description {
                Text(description)
                    .chatFont(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Text(preview.domain)
                .chatFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
