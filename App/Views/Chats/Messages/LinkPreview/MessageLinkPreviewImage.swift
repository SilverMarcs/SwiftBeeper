import SwiftMediaViewer
import SwiftUI

/// A link preview's image across the card's width, cropped to fill. Its
/// space comes from the image's reported size, or the usual 1.91:1 of a
/// page's sharing image, so the row keeps its height while it loads.
struct MessageLinkPreviewImage: View {
    let source: String
    let aspectRatio: CGFloat?

    private static let maxHeight: CGFloat = Device.isMacOrPad ? 260 : 200
    private static let defaultAspectRatio: CGFloat = 1.91

    var body: some View {
        Color.clear
            .aspectRatio(min(max(aspectRatio ?? Self.defaultAspectRatio, 0.5), 4), contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: Self.maxHeight)
            .overlay {
                CachedAsyncImage(url: MatrixMedia.displayURL(for: source), targetSize: MediaBubbleSize.decodePixelSize) {
                    Color.clear
                }
                .scaledToFill()
            }
            .clipped()
            .accessibilityHidden(true)
    }
}
