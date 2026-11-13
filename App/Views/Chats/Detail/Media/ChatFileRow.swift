import QuickLook
import SwiftUI

/// A shared file: its icon, name, size and date. Tapping opens it in Quick Look.
struct ChatFileRow: View {
    let message: Message
    let attachment: Attachment

    @State private var previewURL: URL?
    @State private var isDownloading = false

    var body: some View {
        Button {
            Task { await preview() }
        } label: {
            HStack {
                ZStack {
                    FileTypeIcon(type: attachment.fileType)
                        .opacity(isDownloading ? 0 : 1)
                    if isDownloading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                VStack(alignment: .leading) {
                    Text(attachment.fileName ?? "Attachment")
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    Text(ChatSharedItemCaption.text(for: message, fileSize: attachment.fileSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isDownloading)
        .quickLookPreview($previewURL)
    }

    private func preview() async {
        isDownloading = true
        defer { isDownloading = false }
        previewURL = await attachment.previewFile()
    }
}
