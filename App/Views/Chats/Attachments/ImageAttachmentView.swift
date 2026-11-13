import SwiftMediaViewer
import SwiftUI

struct ImageAttachmentView: View {
    let attachment: Attachment
    let isOutgoing: Bool

    var body: some View {
        let size = MediaBubbleSize.fitting(attachment.size)
        Group {
            if let url = MatrixMedia.displayURL(for: attachment.resolvedURL) {
                if attachment.isGif == true {
                    SMVGIFView(url: url, targetSize: MediaBubbleSize.decodePixelSize)
                } else {
                    SMVImage(url: url, targetSize: MediaBubbleSize.decodePixelSize)
                        .scaledToFill()
                }
            } else {
                Color.clear
            }
        }
        .mediaBubbleFrame(size)
        .subtleBackground()
        .messageBubbleClip(isOutgoing: isOutgoing)
    }
}
