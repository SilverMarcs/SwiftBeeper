import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum DroppedAttachment {
    /// Begin loading inside the drop callback, before access to the provider's
    /// payload expires. Results can be applied to the draft asynchronously.
    @MainActor
    static func beginLoading(from provider: NSItemProvider) -> AsyncThrowingStream<PendingAttachment, Error> {
        let imageTypes: [UTType] = [.png, .jpeg, .heic, .heif, .gif, .tiff, .webP, .bmp, .image]
        let imageType = imageTypes.first { provider.hasItemConformingToTypeIdentifier($0.identifier) }
        let suggestedName = provider.suggestedName

        return AsyncThrowingStream { continuation in
            // Screenshot thumbnails can list private types first. Load an
            // image representation explicitly, as LynkChat does.
            if let imageType {
                provider.loadDataRepresentation(forTypeIdentifier: imageType.identifier) { data, error in
                    guard let data else {
                        continuation.finish(throwing: error ?? CocoaError(.fileReadUnknown))
                        return
                    }
                    let detectedType = CGImageSourceCreateWithData(data as CFData, nil)
                        .flatMap { CGImageSourceGetType($0) }
                        .flatMap { UTType($0 as String) } ?? imageType
                    let ext = detectedType.preferredFilenameExtension ?? "png"
                    let name = suggestedName.map { URL(filePath: $0).deletingPathExtension().lastPathComponent } ?? "Image"
                    continuation.yield(PendingAttachment(
                        fileData: data,
                        fileName: "\(name).\(ext)",
                        mimeType: detectedType.preferredMIMEType ?? "image/png"
                    ))
                    continuation.finish()
                }
            } else {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.item.identifier) { url, error in
                    guard let url else {
                        continuation.finish(throwing: error ?? CocoaError(.fileReadUnknown))
                        return
                    }
                    // The temporary file is removed when this callback returns.
                    do {
                        let data = try Data(contentsOf: url)
                        continuation.yield(PendingAttachment(
                            fileData: data,
                            fileName: url.lastPathComponent,
                            mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                        ))
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }
}
