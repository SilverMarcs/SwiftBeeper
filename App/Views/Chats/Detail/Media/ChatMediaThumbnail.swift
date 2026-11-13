import SwiftMediaViewer
import SwiftUI

/// A square, cropped thumbnail of a photo or a video's poster frame.
struct ChatMediaThumbnail: View {
    let source: String?
    var placeholderSymbol = "photo"

    /// Grid tiles are under 200pt wide, so this stays sharp at 2x and 3x
    /// while holding far fewer pixels than a timeline bubble's decode. A photo
    /// the timeline already decoded larger is reused as is.
    private static let decodePixelSize = 400

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let url = MatrixMedia.displayURL(for: source) {
                    CachedAsyncImage(url: url, targetSize: Self.decodePixelSize) {
                        ChatMediaThumbnailPlaceholder(symbol: placeholderSymbol)
                    }
                    .scaledToFill()
                } else {
                    ChatMediaThumbnailPlaceholder(symbol: placeholderSymbol)
                }
            }
            .clipped()
            .contentShape(.rect)
    }
}
