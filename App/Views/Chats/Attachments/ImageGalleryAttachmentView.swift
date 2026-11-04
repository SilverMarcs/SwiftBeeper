import SwiftMediaViewer
import SwiftUI

/// Photos sent together, shown as a grid of equal squares. SMVGallery owns
/// the fullscreen viewer, which pages through the whole set.
struct ImageGalleryAttachmentView: View {
    let messages: [Message]

    var body: some View {
        let urls = messages.compactMap { MatrixMedia.displayURL(for: $0.attachments?.first?.resolvedURL) }
        let layout = ImageGalleryLayout(imageCount: urls.count)
        SMVGallery(images: urls, targetSize: MediaBubbleSize.decodePixelSize) {
            Grid(horizontalSpacing: ImageGalleryLayout.spacing, verticalSpacing: ImageGalleryLayout.spacing) {
                ForEach(layout.rows, id: \.self) { row in
                    GridRow {
                        ForEach(row, id: \.self) { index in
                            ImageGalleryTile(
                                url: urls[index],
                                index: index,
                                imageCount: urls.count,
                                side: layout.tileSide,
                                hiddenCount: layout.hiddenCount(onTile: index)
                            )
                        }
                    }
                }
            }
        }
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
    }
}
