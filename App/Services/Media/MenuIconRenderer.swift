import CoreGraphics
import Foundation
import ImageIO

/// Draws small square icons for menus, which show a bitmap at its own size
/// instead of fitting it to the row the way a view would.
nonisolated enum MenuIconRenderer {
    /// The image file at `url`, drawn into a square `pixelSize` wide. A
    /// rounded icon fills the square and is clipped to a rounded rectangle;
    /// otherwise the image keeps its shape and fits inside.
    static func icon(contentsOf url: URL, pixelSize: Int, rounded: Bool) -> CGImage? {
        guard pixelSize > 0,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: pixelSize * 2,
              ] as CFDictionary),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: pixelSize,
                  height: pixelSize,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ),
              thumbnail.width > 0, thumbnail.height > 0
        else { return nil }

        let side = CGFloat(pixelSize)
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        if rounded {
            let radius = side * 0.22
            context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.clip()
        }
        let width = CGFloat(thumbnail.width), height = CGFloat(thumbnail.height)
        let scale = rounded ? max(side / width, side / height) : min(side / width, side / height)
        let drawn = CGSize(width: width * scale, height: height * scale)
        context.interpolationQuality = .high
        context.draw(thumbnail, in: CGRect(
            x: (side - drawn.width) / 2,
            y: (side - drawn.height) / 2,
            width: drawn.width,
            height: drawn.height
        ))
        return context.makeImage()
    }
}
