import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Local previews of a picked attachment, shared by the composer and the
/// sending bubble before the upload has a Matrix URL.
extension PendingAttachment {
    /// Decodes the picked image data; nil for non-images. Decoding is not
    /// cached, so call it once per render.
    func decodedImage() -> (image: Image, size: CGSize)? {
        guard mimeType.hasPrefix("image/") else { return nil }
        #if os(macOS)
        guard let image = NSImage(data: fileData) else { return nil }
        return (Image(nsImage: image), image.size)
        #else
        guard let image = UIImage(data: fileData) else { return nil }
        return (Image(uiImage: image), image.size)
        #endif
    }

    /// The placeholder symbol for attachments without an image preview.
    var symbolName: String {
        if mimeType.hasPrefix("video/") { return "video" }
        if mimeType.hasPrefix("audio/") { return "waveform" }
        return "doc"
    }
}
