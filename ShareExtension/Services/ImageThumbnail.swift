import CoreGraphics
import Foundation
import ImageIO

/// Small decoded images, so previews don't hold full-resolution bitmaps in
/// the extension's limited memory.
nonisolated enum ImageThumbnail {
    static func make(from data: Data, maximumPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return make(from: source, maximumPixelSize: maximumPixelSize)
    }

    static func make(contentsOf url: URL, maximumPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return make(from: source, maximumPixelSize: maximumPixelSize)
    }

    private static func make(from source: CGImageSource, maximumPixelSize: Int) -> CGImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
