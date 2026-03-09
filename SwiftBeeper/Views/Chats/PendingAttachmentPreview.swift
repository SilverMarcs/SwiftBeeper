import SwiftUI

struct PendingAttachmentPreview: View {
    let pending: PendingAttachment
    let isSending: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: attachmentIcon)
                .font(.title2)
                .foregroundStyle(.secondary)

            Text(pending.fileName)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: 150, height: 50)
        .glassEffect(in: .rect(cornerRadius: 12))
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
            .offset(x: 4, y: -4)
            .disabled(isSending)
        }
    }

    private var attachmentIcon: String {
        if pending.mimeType.hasPrefix("image/") { return "photo" }
        if pending.mimeType.hasPrefix("video/") { return "video" }
        if pending.mimeType.hasPrefix("audio/") { return "waveform" }
        return "doc"
    }
}
