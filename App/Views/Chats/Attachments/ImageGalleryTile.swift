import SwiftMediaViewer
import SwiftUI

/// One square photo in a gallery grid. Tapping it opens the gallery's
/// fullscreen viewer on this photo.
struct ImageGalleryTile: View {
    let url: URL
    let index: Int
    let imageCount: Int
    let side: CGFloat
    /// Photos beyond the grid, counted over this tile when nonzero.
    let hiddenCount: Int

    var body: some View {
        SMVGalleryItem(index: index) {
            CachedAsyncImage(url: url, targetSize: MediaBubbleSize.decodePixelSize)
                .scaledToFill()
                .frame(width: side, height: side)
                .clipped()
                .overlay {
                    if hiddenCount > 0 {
                        Rectangle()
                            .fill(.black.opacity(0.45))
                            .overlay {
                                Text("+\(hiddenCount)")
                                    .font(.title2)
                                    .bold()
                                    .foregroundStyle(.white)
                            }
                    }
                }
        }
        .accessibilityLabel("Photo \(index + 1) of \(imageCount)")
    }
}
