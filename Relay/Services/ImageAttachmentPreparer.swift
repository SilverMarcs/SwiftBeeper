import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Prepares static images for messaging without decoding the full-resolution
/// source on the main actor. Images already below the byte limit pass through
/// unchanged, as do animated images whose frames must be preserved.
enum ImageAttachmentPreparer {
    nonisolated static let maximumByteCount = 800 * 1024
    nonisolated static let initialMaximumPixelSize = 2_048

    nonisolated static func prepare(_ attachment: PendingAttachment) async -> PendingAttachment {
        guard attachment.mimeType.hasPrefix("image/"),
              attachment.fileData.count > maximumByteCount else {
            return attachment
        }

        return await Task.detached(priority: .userInitiated) {
            prepareSynchronously(attachment)
        }.value
    }

    nonisolated private static func prepareSynchronously(_ attachment: PendingAttachment) -> PendingAttachment {
        let sourceOptions = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: false
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(attachment.fileData as CFData, sourceOptions),
              CGImageSourceGetCount(source) == 1,
              let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = sourceProperties[kCGImagePropertyPixelWidth] as? Int,
              let height = sourceProperties[kCGImagePropertyPixelHeight] as? Int else {
            return attachment
        }

        let sourceMaximumPixelSize = max(width, height)
        guard sourceMaximumPixelSize > 0 else { return attachment }

        let destinationType = preferredDestinationType(for: source)
        let outputType = UTType(destinationType as String)
        let outputMimeType = outputType?.preferredMIMEType ?? attachment.mimeType
        let outputFileName = preparedFileName(
            attachment.fileName,
            preferredExtension: outputType?.preferredFilenameExtension
        )

        var maximumPixelSize = min(sourceMaximumPixelSize, initialMaximumPixelSize)
        var smallestResult: Data?

        while maximumPixelSize >= 64 {
            guard let image = makeThumbnail(from: source, maximumPixelSize: maximumPixelSize) else {
                return attachment
            }

            for quality in compressionQualities(for: destinationType) {
                guard let encoded = encode(image, type: destinationType, quality: quality) else {
                    continue
                }
                if encoded.count < (smallestResult?.count ?? .max) {
                    smallestResult = encoded
                }
                if encoded.count <= maximumByteCount {
                    return PendingAttachment(
                        id: attachment.id,
                        fileData: encoded,
                        fileName: outputFileName,
                        mimeType: outputMimeType
                    )
                }
            }

            maximumPixelSize = Int(Double(maximumPixelSize) * 0.8)
        }

        guard let smallestResult, smallestResult.count < attachment.fileData.count else {
            return attachment
        }
        return PendingAttachment(
            id: attachment.id,
            fileData: smallestResult,
            fileName: outputFileName,
            mimeType: outputMimeType
        )
    }

    nonisolated private static func makeThumbnail(from source: CGImageSource, maximumPixelSize: Int) -> CGImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldAllowFloat: false
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    nonisolated private static func preferredDestinationType(for source: CGImageSource) -> CFString {
        let fallback = UTType.jpeg.identifier as CFString
        guard let sourceType = CGImageSourceGetType(source) else { return fallback }
        let writableTypes = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return writableTypes.contains(sourceType as String) ? sourceType : fallback
    }

    nonisolated private static func compressionQualities(for type: CFString) -> [Double] {
        let uniformType = UTType(type as String)
        if uniformType?.conforms(to: .jpeg) == true || uniformType?.conforms(to: .heic) == true {
            return [0.82, 0.72, 0.62, 0.52, 0.42]
        }
        return [1]
    }

    nonisolated private static func encode(_ image: CGImage, type: CFString, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type, 1, nil) else {
            return nil
        }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    nonisolated private static func preparedFileName(_ fileName: String, preferredExtension: String?) -> String {
        guard let preferredExtension, !preferredExtension.isEmpty else { return fileName }
        let existingExtension = URL(filePath: fileName).pathExtension
        guard existingExtension.caseInsensitiveCompare(preferredExtension) != .orderedSame else {
            return fileName
        }
        let stem = URL(filePath: fileName).deletingPathExtension().lastPathComponent
        return "\(stem).\(preferredExtension)"
    }
}
