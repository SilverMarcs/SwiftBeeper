import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct OutgoingAttachmentView: View {
    let attachment: PendingAttachment
    let progress: Double?
    let state: OutgoingMessageState

    private var isImage: Bool {
        attachment.mimeType.hasPrefix("image/")
    }

    var body: some View {
        Group {
            if isImage, let image = makeImage() {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: imageSize.width, height: imageSize.height)
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
            switch state {
            case .sending:
                ZStack {
                    Color.black.opacity(0.18)
                    uploadProgressView
                }
                .clipShape(.rect(cornerRadius: 12))
            case .failed:
                Color.black.opacity(0.12)
                    .clipShape(.rect(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private var uploadProgressView: some View {
        if let progress, progress < 1 {
            ProgressView(value: progress)
                .progressViewStyle(.circular)
                .tint(.white)
        } else {
            ProgressView()
                .tint(.white)
        }
    }

    private var imageSize: CGSize {
        let maxWidth: CGFloat = Device.isMacOrPad ? 400 : 275
        let maxHeight: CGFloat = 500
        guard let sourceSize = platformImageSize, sourceSize.width > 0, sourceSize.height > 0 else {
            return CGSize(width: maxWidth, height: maxWidth)
        }

        let scale = min(maxWidth / sourceSize.width, maxHeight / sourceSize.height, 1)
        return CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
    }

    private var platformImageSize: CGSize? {
        #if os(macOS)
        NSImage(data: attachment.fileData)?.size
        #else
        UIImage(data: attachment.fileData)?.size
        #endif
    }

    private var attachmentIcon: String {
        if attachment.mimeType.hasPrefix("video/") { return "video" }
        if attachment.mimeType.hasPrefix("audio/") { return "waveform" }
        return "doc"
    }

    private func makeImage() -> Image? {
        #if os(macOS)
        guard let image = NSImage(data: attachment.fileData) else { return nil }
        return Image(nsImage: image)
        #else
        guard let image = UIImage(data: attachment.fileData) else { return nil }
        return Image(uiImage: image)
        #endif
    }
}
