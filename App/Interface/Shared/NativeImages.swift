import Foundation
import ImageIO
#if os(macOS)
import AppKit
typealias NativeImage = NSImage
#else
import UIKit
typealias NativeImage = UIImage
#endif

@MainActor
enum NativeImages {
    private static let cache: NSCache<NSString, NativeImage> = {
        let cache = NSCache<NSString, NativeImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    static func image(_ source: String, maximumSize: Int = 700, animated: Bool = false) async -> NativeImage? {
        let key = "\(maximumSize):\(animated):\(source)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let request = AuthenticatedImageLoader.buildRequest(for: source) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled, (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? true else { return nil }
            guard let image = animated ? await animatedImage(data, maximumSize: maximumSize) : await thumbnail(data, maximumSize: maximumSize) else { return nil }
            cache.setObject(image, forKey: key, cost: animated ? 24 * 1024 * 1024 : maximumSize * maximumSize * 4)
            return image
        } catch { return nil }
    }

    static func thumbnail(_ data: Data, maximumSize: Int = 120) async -> NativeImage? {
        let cgImage = await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil as CGImage? }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumSize,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        }.value
        guard !Task.isCancelled, let cgImage else { return nil }
        #if os(macOS)
        return NSImage(cgImage: cgImage, size: .zero)
        #else
        return UIImage(cgImage: cgImage)
        #endif
    }

    private static func animatedImage(_ data: Data, maximumSize: Int) async -> NativeImage? {
        #if os(macOS)
        return NSImage(data: data)
        #else
        let decoded = await Task.detached(priority: .utility) { () -> ([CGImage], Double)? in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            let count = CGImageSourceGetCount(source)
            guard count > 1 else { return nil }
            // Bound decoded frame memory, including GIFs with many frames.
            let pixels = max(1, min(maximumSize, Int(sqrt(Double(24 * 1024 * 1024 / 4 / count)))))
            var frames: [CGImage] = []; var duration = 0.0
            for index in 0..<count {
                guard !Task.isCancelled else { return nil }
                guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels] as CFDictionary) else { continue }
                let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
                let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                let delay = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? gif?[kCGImagePropertyGIFDelayTime] as? Double ?? 0.1
                frames.append(frame); duration += delay < 0.02 ? 0.1 : delay
            }
            return frames.isEmpty ? nil : (frames, duration)
        }.value
        guard !Task.isCancelled else { return nil }
        guard let decoded else { return await thumbnail(data, maximumSize: maximumSize) }
        return UIImage.animatedImage(with: decoded.0.map { UIImage(cgImage: $0) }, duration: decoded.1)
        #endif
    }

    static func clear() { cache.removeAllObjects(); AuthenticatedImageLoader.clearTempFiles() }
}
