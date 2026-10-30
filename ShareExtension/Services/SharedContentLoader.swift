import Foundation
import UniformTypeIdentifiers

/// Reads the share sheet's item providers into a `SharedContent`.
enum SharedContentLoader {
    /// Share extensions run under a tight memory limit, and the file is held
    /// in memory until it is staged.
    private static let maximumAttachmentBytes = 50 * 1024 * 1024

    static func load(_ providers: [NSItemProvider]) async throws -> SharedContent {
        var content = SharedContent()
        var lines: [String] = []
        for provider in providers {
            if content.attachment == nil, let type = attachmentType(of: provider) {
                content.attachment = try await loadAttachment(from: provider, type: type)
            } else if let line = await loadText(from: provider) {
                lines.append(line)
            }
        }
        content.text = lines.joined(separator: "\n")
        return content
    }

    /// A media type when there is one, else any file type that isn't a link or text.
    private static func attachmentType(of provider: NSItemProvider) -> UTType? {
        let types = provider.registeredContentTypes
        return types.first { $0.conforms(to: .image) || $0.conforms(to: .audiovisualContent) }
            ?? types.first { $0.conforms(to: .data) && !$0.conforms(to: .url) && !$0.conforms(to: .text) }
    }

    private static func loadAttachment(from provider: NSItemProvider, type: UTType) async throws -> PendingAttachment {
        let suggestedName = provider.suggestedName
        let maximumBytes = maximumAttachmentBytes
        return try await withCheckedThrowingContinuation { continuation in
            // The file is deleted once this handler returns, so read it here.
            _ = provider.loadFileRepresentation(for: type, openInPlace: false) { @Sendable url, _, error in
                guard let url else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    return
                }
                do {
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= maximumBytes else { throw ShareError.attachmentTooLarge }
                    let data = try Data(contentsOf: url)
                    continuation.resume(returning: PendingAttachment(
                        fileData: data,
                        fileName: fileName(suggestedName, fallback: url, type: type),
                        mimeType: type.preferredMIMEType ?? "application/octet-stream"
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// A web link or plain text; file links are left out.
    private static func loadText(from provider: NSItemProvider) async -> String? {
        if provider.canLoadObject(ofClass: NSURL.self) {
            let link = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: NSURL.self) { @Sendable object, _ in
                    let url = object as? URL
                    continuation.resume(returning: url?.isFileURL == false ? url?.absoluteString : nil)
                }
            }
            return link
        }
        guard provider.canLoadObject(ofClass: NSString.self) else { return nil }
        let text = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { @Sendable object, _ in
                continuation.resume(returning: object as? String)
            }
        }
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// The provider's suggested name with the type's extension, or the
    /// temporary file's name.
    private nonisolated static func fileName(_ suggestedName: String?, fallback: URL, type: UTType) -> String {
        guard let suggestedName, !suggestedName.isEmpty else { return fallback.lastPathComponent }
        guard let fileExtension = type.preferredFilenameExtension,
              URL(filePath: suggestedName).pathExtension.isEmpty else { return suggestedName }
        return "\(suggestedName).\(fileExtension)"
    }
}
