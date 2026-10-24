import SwiftUI
import SwiftMediaViewer

struct VideoAttachmentPoster: View {
    let source: String?

    var body: some View {
        if let url = MatrixMedia.displayURL(for: source) {
            CachedAsyncImage(url: url, targetSize: 650) {
                Color.clear.subtleBackground()
            }
            .scaledToFill()
        } else {
            Color.clear.subtleBackground()
        }
    }
}
