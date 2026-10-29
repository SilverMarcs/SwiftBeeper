import Photos
import UniformTypeIdentifiers

enum PhotoLibrarySaver {
    static func save(_ attachment: Attachment) async throws {
        guard let contentType = attachment.photoLibraryContentType else {
            throw PhotoLibrarySaveError.unsupportedMedia
        }

        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            throw PhotoLibrarySaveError.permissionDenied
        }
        guard let source = attachment.resolvedURL,
              let file = await MatrixMedia.localFile(for: source) else {
            throw PhotoLibrarySaveError.unavailableMedia
        }

        let resourceType: PHAssetResourceType = contentType.conforms(to: .movie) ? .video : .photo
        let fileName = attachment.fileName.map { URL(filePath: $0).lastPathComponent }
        try await PHPhotoLibrary.shared().performChanges {
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = fileName
            // Cache paths can lack an extension. Give Photos the sender's type
            // when known, and otherwise let it infer the format from the media.
            if contentType != .image && contentType != .movie {
                options.contentType = contentType
            }
            PHAssetCreationRequest.forAsset().addResource(with: resourceType, fileURL: file, options: options)
        }
    }
}

extension Attachment {
    /// Also recognizes photos and videos sent as ordinary file attachments.
    var photoLibraryContentType: UTType? {
        if let contentType = mimeType.flatMap({ UTType(mimeType: $0) }),
           contentType.conforms(to: .image) || contentType.conforms(to: .movie) {
            return contentType
        }
        if let contentType = fileName.flatMap({ UTType(filenameExtension: URL(filePath: $0).pathExtension) }),
           contentType.conforms(to: .image) || contentType.conforms(to: .movie) {
            return contentType
        }
        switch type {
        case .image: return .image
        case .video: return .movie
        default: return nil
        }
    }
}
