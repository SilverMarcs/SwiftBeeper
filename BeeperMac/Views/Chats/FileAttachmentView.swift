import SwiftUI

struct FileAttachmentView: View {
    let attachment: Attachment
    let isOutgoing: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName ?? "Attachment")
                    .font(.callout)
                    .lineLimit(1)

                if let fileSize = attachment.fileSize {
                    Text(formattedFileSize(fileSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isOutgoing ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.background.tertiary))
        .clipShape(.rect(cornerRadius: 12))
    }

    private func formattedFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
