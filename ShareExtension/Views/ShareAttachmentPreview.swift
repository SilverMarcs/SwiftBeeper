import SwiftUI

/// A thumbnail for images, else the file's kind and name.
struct ShareAttachmentPreview: View {
    let attachment: PendingAttachment
    let image: CGImage?

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 160)
                .clipShape(.rect(cornerRadius: 12))
        } else {
            Label(attachment.fileName, systemImage: symbolName)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
    }

    private var symbolName: String {
        if attachment.mimeType.hasPrefix("video/") { return "video" }
        if attachment.mimeType.hasPrefix("audio/") { return "waveform" }
        return "doc"
    }
}
