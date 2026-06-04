import SwiftMediaViewer
import SwiftUI

struct ImageAttachmentView: View {
    let attachment: Attachment

    private let maxWidth: CGFloat = 330
    private let maxHeight: CGFloat = 500
    /// Decode size in pixels — large enough that SMV's fullscreen viewer
    /// (which reuses the same cached decode) stays sharp.
    private let targetSize = 650

    var body: some View {
        Group {
            if let url = AuthenticatedImageLoader.displayURL(for: attachment.resolvedURL) {
                if attachment.isGif == true {
                    SMVGIFView(url: url, targetSize: targetSize)
                } else {
                    SMVImage(url: url, targetSize: targetSize)
                        .scaledToFill()
                }
            } else {
                Color.clear
            }
        }
        .frame(width: imageSize.width, height: imageSize.height)
        .subtleBackground()
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
    }

    private var imageSize: CGSize {
        guard let w = attachment.size?.width, let h = attachment.size?.height,
              w > 0, h > 0 else {
            return CGSize(width: maxWidth, height: maxWidth)
        }

        let aspectRatio = CGFloat(w) / CGFloat(h)
        var width = min(CGFloat(w), maxWidth)
        var height = width / aspectRatio

        if height > maxHeight {
            height = maxHeight
            width = height * aspectRatio
        }

        return CGSize(width: width, height: height)
    }
}
