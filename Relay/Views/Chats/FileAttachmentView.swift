import QuickLook
import SwiftUI

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
                    Image(systemName: "doc")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

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
            .bubbleBackground(isOutgoing: isOutgoing)
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .quickLookPreview($previewURL)
    }

    private func downloadAndPreview() async {
        guard let srcURL = attachment.resolvedURL else { return }

        let fileExtension = (attachment.fileName as? NSString)?.pathExtension ?? "dat"

        isDownloading = true
        defer { isDownloading = false }

        guard let localURL = await AuthenticatedImageLoader.downloadToTempFile(
            urlString: srcURL,
            fileExtension: fileExtension
        ) else { return }

        previewURL = localURL
    }

    private func formattedFileSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
