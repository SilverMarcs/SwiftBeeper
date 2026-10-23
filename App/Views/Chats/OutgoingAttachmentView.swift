import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OutgoingAttachmentView: View {
    let attachment: PendingAttachment
    let message: OutgoingMessage

    private var isImage: Bool {
        attachment.mimeType.hasPrefix("image/")
    }

    var body: some View {
        Group {
            if let decoded = decodedImage() {
                let size = fittedSize(for: decoded.size)
                decoded.image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .subtleBackground()
                    .clipShape(.rect(cornerRadius: 12))
            } else {
                HStack {
                    Image(systemName: attachmentIcon)
                        .font(.title)

                    Text(attachment.fileName)
                        .font(.callout)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .foregroundStyle(.white)
                .padding()
                .frame(maxWidth: 275, minHeight: 64)
                .bubbleBackground(isOutgoing: true)
                .clipShape(.rect(cornerRadius: 12))
            }
        }
        .overlay {
            switch message.state {
            case .sending:
                ZStack {
                    Color.black.opacity(0.18)
                    ProgressView()
                        .tint(.white)
                }
                .clipShape(.rect(cornerRadius: 12))
            case .failed:
                Color.black.opacity(0.12)
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
    }

    private func fittedSize(for sourceSize: CGSize) -> CGSize {
        let maxWidth: CGFloat = Device.isMacOrPad ? 400 : 275
        let maxHeight: CGFloat = 500
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return CGSize(width: maxWidth, height: maxWidth)
        }

        let scale = min(maxWidth / sourceSize.width, maxHeight / sourceSize.height, 1)
        return CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    }

    private var attachmentIcon: String {
        if attachment.mimeType.hasPrefix("video/") { return "video" }
        if attachment.mimeType.hasPrefix("audio/") { return "waveform" }
        return "doc"
    }

    /// Decodes the picked image once per render; its size sets the bubble frame.
    private func decodedImage() -> (image: Image, size: CGSize)? {
        guard isImage else { return nil }
        #if os(macOS)
        guard let image = NSImage(data: attachment.fileData) else { return nil }
        return (Image(nsImage: image), image.size)
        #else
        guard let image = UIImage(data: attachment.fileData) else { return nil }
        return (Image(uiImage: image), image.size)
        #endif
    }
}
