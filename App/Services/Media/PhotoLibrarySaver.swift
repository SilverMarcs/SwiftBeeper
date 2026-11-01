import ImageIO
import Photos
import UniformTypeIdentifiers

enum PhotoLibrarySaver {
    static func save(_ attachment: Attachment) async throws {
        guard let declaredType = attachment.photoLibraryContentType else {
            throw PhotoLibrarySaveError.unsupportedMedia
        }

        let authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard authorization == .authorized || authorization == .limited else {
            throw PhotoLibrarySaveError.permissionDenied
        }
        guard let source = attachment.resolvedURL,
              let cached = await MatrixMedia.localFile(for: source) else {
            throw PhotoLibrarySaveError.unavailableMedia
        }

        // Photos rejects a file whose extension doesn't match its contents
        // (PHPhotosErrorDomain 3302). Cache files have no extension, or
        // `.decrypted` for encrypted media, so hand Photos a copy named for
        // the media's real type.
        let contentType = concreteType(for: declaredType, cachedFile: cached)
        guard let fileExtension = contentType.preferredFilenameExtension,
              let file = await MatrixMedia.temporaryFile(for: source, fileExtension: fileExtension) else {
            throw PhotoLibrarySaveError.unavailableMedia
        }

        let resourceType: PHAssetResourceType = contentType.conforms(to: .movie) ? .video : .photo
        let fileName = attachment.fileName.map { URL(filePath: $0).lastPathComponent }
        try await PHPhotoLibrary.shared().performChanges {
            let options = PHAssetResourceCreationOptions()
            options.originalFilename = fileName
            options.contentType = contentType
            PHAssetCreationRequest.forAsset().addResource(with: resourceType, fileURL: file, options: options)
        }
    }

    /// Narrows the generic image and movie fallbacks to a concrete format.
    /// Images are identified from their bytes; videos default to MPEG-4,
    /// which is what Matrix clients send.
    private static func concreteType(for declaredType: UTType, cachedFile: URL) -> UTType {
        switch declaredType {
        case .image:
            guard let imageSource = CGImageSourceCreateWithURL(cachedFile as CFURL, nil),
                  let identifier = CGImageSourceGetType(imageSource) as String?,
                  let sniffedType = UTType(identifier) else {
                return .jpeg
            }
            return sniffedType
        case .movie:
            return .mpeg4Movie
        default:
            return declaredType
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
