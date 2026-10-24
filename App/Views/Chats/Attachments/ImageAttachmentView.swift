import SwiftMediaViewer
import SwiftUI

struct ImageAttachmentView: View {
    let attachment: Attachment

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
        .frame(width: size.width, height: size.height)
        .subtleBackground()
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
    }
}
