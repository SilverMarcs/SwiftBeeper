import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PendingAttachmentPreview: View {
    let pending: PendingAttachment
    let isSending: Bool
    let onRemove: () -> Void

    private var isImage: Bool {
        pending.mimeType.hasPrefix("image/")
    }

    var body: some View {
        Group {
            if isImage, let image = makeImage() {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(.rect(cornerRadius: 12))
                    .glassEffect(in: .rect(cornerRadius: 12))
            } else {
                VStack(spacing: 4) {
                    Image(systemName: attachmentIcon)
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    Text(pending.fileName)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding()
                .frame(width: 80, height: 80)
                .glassEffect(in: .rect(cornerRadius: 12))
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.white, .secondary)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .padding(5)
            .disabled(isSending)
        }
    }

    private var attachmentIcon: String {
        if pending.mimeType.hasPrefix("video/") { return "video" }
        if pending.mimeType.hasPrefix("audio/") { return "waveform" }
        return "doc"
    }

    private func makeImage() -> Image? {
        #if os(macOS)
        guard let nsImage = NSImage(data: pending.fileData) else { return nil }
        return Image(nsImage: nsImage)
        #else
        guard let uiImage = UIImage(data: pending.fileData) else { return nil }
        return Image(uiImage: uiImage)
        #endif
    }
}
