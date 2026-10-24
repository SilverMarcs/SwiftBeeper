import SwiftMediaViewer
import SwiftUI

struct VideoAttachmentPoster: View {
    let source: String?

    var body: some View {
        if let url = MatrixMedia.displayURL(for: source) {
            CachedAsyncImage(url: url, targetSize: MediaBubbleSize.decodePixelSize) {
                Color.clear.subtleBackground()
            }
            .scaledToFill()
        } else {
            Color.clear.subtleBackground()
        }
    }
}
