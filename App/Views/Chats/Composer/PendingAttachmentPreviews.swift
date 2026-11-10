import CoreGraphics
import Foundation
import ImageIO

/// Downsampled previews of picked images, kept per attachment while it's in
/// the composer or sending. The system evicts them under memory pressure.
enum PendingAttachmentPreviews {
    final class Preview {
        let image: CGImage
        /// The full image's size in pixels, upright.
        let size: CGSize

        init(image: CGImage, size: CGSize) {
            self.image = image
            self.size = size
        }
    }

    private static let cache: NSCache<NSUUID, Preview> = {
        let cache = NSCache<NSUUID, Preview>()
        cache.countLimit = 40
        return cache
    }()

    static func preview(for attachment: PendingAttachment) -> Preview? {
        let key = attachment.id as NSUUID
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithData(attachment.fileData as CFData, nil),
              let image = ImageThumbnail.make(from: attachment.fileData, maximumPixelSize: MediaBubbleSize.decodePixelSize) else {
            return nil
        }
        let preview = Preview(image: image, size: uprightPixelSize(of: source) ?? CGSize(width: image.width, height: image.height))
        cache.setObject(preview, forKey: key)
        return preview
    }

    /// The image's pixel size with its EXIF orientation applied.
    private static func uprightPixelSize(of source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        // Orientations 5 to 8 rotate the image a quarter turn.
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }
}
