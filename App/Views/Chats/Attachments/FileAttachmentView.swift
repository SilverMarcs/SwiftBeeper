import QuickLook
import SwiftUI
import UniformTypeIdentifiers

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
                    FileTypeIcon(type: fileType)
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

    /// The file name's extension, if it has one.
    private var fileNameExtension: String? {
        guard let fileName = attachment.fileName else { return nil }
        let pathExtension = URL(filePath: fileName).pathExtension
        return pathExtension.isEmpty ? nil : pathExtension
    }

    private var fileType: UTType {
        if let mimeType = attachment.mimeType, let type = UTType(mimeType: mimeType) {
            return type
        }
        let pathExtension = fileNameExtension
            ?? attachment.resolvedURL.flatMap(URL.init(string:))?.pathExtension
            ?? ""
        guard !pathExtension.isEmpty else { return .data }
        return UTType(filenameExtension: pathExtension) ?? .data
    }

    private func downloadAndPreview() async {
        guard let source = attachment.resolvedURL else { return }
        // Quick Look picks a viewer from the extension, so fall back to the
        // MIME type's when the file name has none.
        let fileExtension = fileNameExtension ?? fileType.preferredFilenameExtension ?? "dat"

        isDownloading = true
        defer { isDownloading = false }
        previewURL = await MatrixMedia.temporaryFile(for: source, fileExtension: fileExtension)
    }
}

/// The system icon for the file's type on macOS, or a matching SF Symbol on
/// iOS, which has no file-type icon API.
private struct FileTypeIcon: View {
    let type: UTType

    var body: some View {
        #if os(macOS)
        Image(nsImage: NSWorkspace.shared.icon(for: type))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 32, height: 32)
        #else
        Image(systemName: symbolName)
            .font(.title)
            .frame(width: 32, height: 32)
            .foregroundStyle(.secondary)
        #endif
    }

    #if !os(macOS)
    private var symbolName: String {
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return "film" }
        if type.conforms(to: .audio) { return "music.note" }
        if type.conforms(to: .pdf) { return "doc.richtext" }
        if type.conforms(to: .archive) || type.conforms(to: .zip) { return "doc.zipper" }
        if type.conforms(to: .text) { return "doc.text" }
        return "doc"
    }
    #endif
}
