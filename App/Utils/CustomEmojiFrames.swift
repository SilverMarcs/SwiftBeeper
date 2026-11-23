import CoreGraphics
import Foundation
import ImageIO

/// A custom emoji's frames, decoded at the size shown: one for a still image,
/// several for a GIF, animated PNG or WebP. Shared by every view showing the
/// emoji at that size.
final class CustomEmojiFrames: @unchecked Sendable {
    let images: [CGImage]
    /// When each frame starts, as fractions of `duration`, then 1.
    let keyTimes: [Double]
    let duration: TimeInterval

    var isAnimated: Bool { images.count > 1 }

    private init(images: [CGImage], keyTimes: [Double], duration: TimeInterval) {
        self.images = images
        self.keyTimes = keyTimes
        self.duration = duration
    }

    /// Long animations are cut short rather than held in memory whole.
    private static let frameLimit = 120
    /// Browsers play frames this short or shorter at this delay, as do
    /// the apps the emoji come from.
    private static let minimumFrameDelay = 0.02
    private static let defaultFrameDelay = 0.1

    nonisolated(unsafe) private static let cache: NSCache<NSString, CustomEmojiFrames> = {
        let cache = NSCache<NSString, CustomEmojiFrames>()
        // In decoded bytes: a long GIF holds over a megabyte of frames.
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    private static func cacheKey(_ source: String, pixelSize: Int) -> NSString {
        "\(pixelSize) \(source)" as NSString
    }

    /// The frames already decoded, so a view scrolling back in draws at once.
    static func cached(_ source: String, pixelSize: Int) -> CustomEmojiFrames? {
        cache.object(forKey: cacheKey(source, pixelSize: pixelSize))
    }

    /// Downloads the emoji if needed and decodes it, or nil when it can't be.
    static func load(_ source: String, pixelSize: Int) async -> CustomEmojiFrames? {
        if let frames = cached(source, pixelSize: pixelSize) { return frames }
        guard let file = await MatrixMedia.localFile(for: source),
              let frames = await decode(file, pixelSize: pixelSize) else { return nil }
        let cost = frames.images.reduce(0) { $0 + $1.bytesPerRow * $1.height }
        cache.setObject(frames, forKey: cacheKey(source, pixelSize: pixelSize), cost: cost)
        return frames
    }

    @concurrent
    private nonisolated static func decode(_ file: URL, pixelSize: Int) async -> CustomEmojiFrames? {
        guard let imageSource = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(pixelSize, 1),
        ] as CFDictionary
        let count = min(CGImageSourceGetCount(imageSource), frameLimit)
        var images: [CGImage] = []
        var delays: [Double] = []
        for index in 0..<count {
            guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, index, options) else { continue }
            images.append(image)
            delays.append(frameDelay(of: imageSource, at: index))
        }
        guard !images.isEmpty else { return nil }
        let duration = delays.reduce(0, +)
        var start = 0.0
        var keyTimes: [Double] = []
        for delay in delays {
            keyTimes.append(start / duration)
            start += delay
        }
        keyTimes.append(1)
        return CustomEmojiFrames(images: images, keyTimes: keyTimes, duration: duration)
    }

    private nonisolated static func frameDelay(of imageSource: CGImageSource, at index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any] else {
            return defaultFrameDelay
        }
        let containers: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
        ]
        for (container, unclamped, clamped) in containers {
            guard let frame = properties[container] as? [CFString: Any] else { continue }
            let delay = (frame[unclamped] as? Double) ?? (frame[clamped] as? Double) ?? defaultFrameDelay
            return delay <= minimumFrameDelay ? defaultFrameDelay : delay
        }
        return defaultFrameDelay
    }
}
