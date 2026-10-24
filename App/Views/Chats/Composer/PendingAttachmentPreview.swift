import SwiftUI

struct PendingAttachmentPreview: View {
    @Environment(InputManager.self) private var input

    let pending: PendingAttachment

    var body: some View {
        Group {
            if let image = pending.decodedImage()?.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipShape(.rect(cornerRadius: 12))
                    .glassEffect(in: .rect(cornerRadius: 12))
            } else {
                VStack(spacing: 4) {
                    Image(systemName: pending.symbolName)
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
                input.removePendingAttachment(id: pending.id)
            } label: {
                Label("Remove Attachment", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.caption)
                    .foregroundStyle(.white, .secondary)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .padding(5)
        }
    }
}
