import SwiftMediaViewer
import SwiftUI

struct PendingAttachmentPreview: View {
    let pending: PendingAttachment
    /// The photo's URL for SwiftMediaViewer; nil for other files.
    let imageURL: URL?
    /// The photo's position in the bar's gallery.
    let galleryIndex: Int?
    let remove: () -> Void

    var body: some View {
        Group {
            if let imageURL, let galleryIndex {
                SMVGalleryItem(index: galleryIndex) {
                    // Loading through SwiftMediaViewer at the viewer's size
                    // warms its cache, so the viewer zooms out of the photo
                    // itself, not a placeholder. The local preview fills in
                    // until then, and stays decoded for the sending bubble.
                    CachedAsyncImage(url: imageURL, targetSize: MediaBubbleSize.decodePixelSize) {
                        if let image = pending.decodedImage()?.image {
                            image.resizable()
                        }
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(.rect(cornerRadius: 12))
                    .glassEffect(in: .rect(cornerRadius: 12))
                }
                .accessibilityLabel("Photo \(galleryIndex + 1)")
            } else {
                VStack(spacing: 4) {
                    Image(systemName: pending.symbolName)
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    Text(pending.fileName)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding()
                .frame(width: 80, height: 80)
                .glassEffect(in: .rect(cornerRadius: 12))
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                remove()
            } label: {
                Label("Remove Attachment", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.white, .secondary)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .padding(5)
        }
    }
}
