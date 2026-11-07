import SwiftMediaViewer
import SwiftUI

/// One square photo in a gallery grid, as wide as its column. Tapping it
/// opens the gallery's fullscreen viewer on this photo.
struct ImageGalleryTile: View {
    let url: URL
    let index: Int
    let imageCount: Int
    /// Photos beyond the grid, counted over this tile when nonzero.
    let hiddenCount: Int

    var body: some View {
        SMVGalleryItem(index: index) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    CachedAsyncImage(url: url, targetSize: MediaBubbleSize.decodePixelSize)
                        .scaledToFill()
                }
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
