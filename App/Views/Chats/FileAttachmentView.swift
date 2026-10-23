import QuickLook
import SwiftUI
import UniformTypeIdentifiers

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
                    fileIcon
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

        guard let localURL = await MatrixMedia.temporaryFile(for: srcURL, fileExtension: fileExtension) else { return }

        previewURL = localURL
    }

    private var fileIcon: some View {
        #if os(macOS)
        Image(nsImage: NSWorkspace.shared.icon(for: utType))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 32, height: 32)
        #else
        // iOS has no NSWorkspace file-type icon API; map the UTType to an SF Symbol.
        Image(systemName: symbolName(for: utType))
            .font(.title)
            .frame(width: 32, height: 32)
            .foregroundStyle(.secondary)
        #endif
    }

    #if !os(macOS)
    private func symbolName(for type: UTType) -> String {
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return "film" }
        if type.conforms(to: .audio) { return "music.note" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .archive) || type.conforms(to: .zip) { return "doc.zipper" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }
    #endif

    private var utType: UTType {
        if let mime = attachment.mimeType,
           let type = UTType(mimeType: mime) {
            return type
        }
        let ext = (attachment.fileName as NSString?)?.pathExtension
            ?? attachment.resolvedURL.flatMap(URL.init(string:))?.pathExtension
            ?? ""
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) {
            return type
        }
        return .data
    }
}
