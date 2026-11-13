import QuickLook
import SwiftUI

/// A generic file bubble that opens the file in Quick Look.
struct FileAttachmentView: View {
    let attachment: Attachment
    let isOutgoing: Bool

    @State private var previewURL: URL?
    @State private var isDownloading = false

    var body: some View {
        Button {
            guard !isDownloading else { return }
            Task { await downloadAndPreview() }
        } label: {
            HStack(spacing: 8) {
                if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    FileTypeIcon(type: attachment.fileType)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.fileName ?? "Attachment")
                        .font(.callout)
                        .lineLimit(1)

                    if let fileSize = attachment.fileSize {
                        Text(Int64(fileSize).formatted(.byteCount(style: .file)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .bubbleBackground(isOutgoing: isOutgoing)
            .messageBubbleClip(isOutgoing: isOutgoing)
        }
        .buttonStyle(.plain)
        .quickLookPreview($previewURL)
    }

    private func downloadAndPreview() async {
        isDownloading = true
        defer { isDownloading = false }
        previewURL = await attachment.previewFile()
    }
}
