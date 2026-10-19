import Foundation
import UniformTypeIdentifiers
import SwiftOGG

enum AttachmentFiles {
    static func load(_ attachment: Attachment) async throws -> URL {
        guard let source = attachment.resolvedURL else { throw MatrixError.invalidRequest }
        let ext = URL(filePath: attachment.fileName ?? "").pathExtension
        let fallback = UTType(mimeType: (attachment.mimeType ?? "").components(separatedBy: ";")[0])?.preferredFilenameExtension ?? "bin"
        guard let url = await AuthenticatedImageLoader.downloadToTempFile(urlString: source, fileExtension: ext.isEmpty ? fallback : ext) else {
            throw MatrixError.operationFailed
        }
        return url
    }

    static func playableAudio(_ attachment: Attachment) async throws -> URL {
        let file = try await load(attachment)
        let mime = attachment.mimeType?.lowercased() ?? ""
        guard mime.contains("ogg") || mime.contains("opus") || file.pathExtension == "ogg" else { return file }
        let destination = file.deletingPathExtension().appendingPathExtension("m4a")
        try await Task.detached(priority: .userInitiated) {
            try OGGConverter.convertOpusOGGToM4aFile(src: file, dest: destination)
        }.value
        return destination
    }
}
