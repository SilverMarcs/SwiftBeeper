import Foundation
import UniformTypeIdentifiers

extension Attachment {
    /// The file name's extension, if it has one.
    var fileNameExtension: String? {
        guard let fileName else { return nil }
        let pathExtension = URL(filePath: fileName).pathExtension
        return pathExtension.isEmpty ? nil : pathExtension
    }

    /// The file's type, from its MIME type or else its extension.
    var fileType: UTType {
        if let mimeType, let type = UTType(mimeType: mimeType) {
            return type
        }
        let pathExtension = fileNameExtension
            ?? resolvedURL.flatMap(URL.init(string:))?.pathExtension
            ?? ""
        guard !pathExtension.isEmpty else { return .data }
        return UTType(filenameExtension: pathExtension) ?? .data
    }

    /// A temporary copy of the file for Quick Look, which picks a viewer from
    /// the extension, so the MIME type's stands in when the name has none.
    func previewFile() async -> URL? {
        guard let source = resolvedURL else { return nil }
        let fileExtension = fileNameExtension ?? fileType.preferredFilenameExtension ?? "dat"
        return await MatrixMedia.temporaryFile(for: source, fileExtension: fileExtension)
    }
}
