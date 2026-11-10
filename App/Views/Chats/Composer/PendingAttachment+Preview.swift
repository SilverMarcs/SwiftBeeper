import ImageIO
import SwiftUI

/// Local previews of a picked attachment, shared by the composer and the
/// sending bubble before the upload has a Matrix URL.
extension PendingAttachment {
    /// A downsampled preview of the picked image, with the image's full size
    /// for bubble layout; nil for non-images. Decoded once per attachment,
    /// since a full camera photo is tens of megabytes of bitmap and these
    /// views re-render often.
    func decodedImage() -> (image: Image, size: CGSize)? {
        guard mimeType.hasPrefix("image/") else { return nil }
        guard let preview = PendingAttachmentPreviews.preview(for: self) else { return nil }
        return (Image(decorative: preview.image, scale: 1), preview.size)
    }

    /// The placeholder symbol for attachments without an image preview.
    var symbolName: String {
        if mimeType.hasPrefix("video/") { return "video" }
        if mimeType.hasPrefix("audio/") { return "waveform" }
        return "doc"
    }
}
