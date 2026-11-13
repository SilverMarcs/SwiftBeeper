import SwiftMediaViewer
import SwiftUI

/// One photo or video in a media grid. Photos open in the grid's gallery;
/// videos play in Quick Look through `playVideo`.
struct ChatMediaTile: View {
    let attachment: Attachment
    /// The photo's place in the grid's gallery; nil for videos.
    let galleryIndex: Int?
    let isPreparingVideo: Bool
    let playVideo: () -> Void

    var body: some View {
        if let galleryIndex {
            SMVGalleryItem(index: galleryIndex) {
                ChatMediaThumbnail(source: attachment.resolvedURL)
            }
            .accessibilityLabel(attachment.isGif == true ? "GIF" : "Photo")
        } else {
            Button(action: playVideo) {
                ChatMediaThumbnail(source: attachment.posterImg, placeholderSymbol: "video")
                    .overlay {
                        ChatMediaVideoBadge(duration: attachment.duration)
                    }
                    .overlay {
                        if isPreparingVideo {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(isPreparingVideo)
            .accessibilityLabel("Video")
        }
    }
}
