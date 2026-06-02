import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum AuthenticatedImageLoader {
    /// In-memory image cache (keyed by URL string) to avoid redundant network fetches
    /// for avatars and images that repeat across views.
    private static let imageCache = NSCache<NSString, ImageWrapper>()

    private static func cachedImage(for urlString: String) -> Image? {
        if let wrapper = imageCache.object(forKey: urlString as NSString),
           let platformImage = wrapper.platformImage {
            #if os(macOS)
            return Image(nsImage: platformImage)
            #else
            return Image(uiImage: platformImage)
            #endif
        }
        return nil
    }

    private static func cacheImageData(_ data: Data, for urlString: String) {
        #if os(macOS)
        if let nsImage = NSImage(data: data) {
            imageCache.setObject(ImageWrapper(image: nsImage), forKey: urlString as NSString)
        }
        #else
        if let uiImage = UIImage(data: data) {
            imageCache.setObject(ImageWrapper(image: uiImage), forKey: urlString as NSString)
        }
        #endif
    }

    static func buildRequest(for urlString: String) -> URLRequest? {
        guard let sourceURL = URL(string: urlString) else { return nil }

        if sourceURL.scheme == "mxc" || sourceURL.scheme == "localmxc" || sourceURL.scheme == "file" {
            guard var components = URLComponents(url: APIConfiguration.assetsProxyURL, resolvingAgainstBaseURL: false) else {
                return nil
            }
            components.queryItems = [URLQueryItem(name: "url", value: urlString)]
            guard let proxyURL = components.url else { return nil }

            var request = URLRequest(url: proxyURL)
            request.setValue("Bearer \(APIClient.accessToken)", forHTTPHeaderField: "Authorization")
            return request
        }

        return URLRequest(url: sourceURL)
    }

    static func loadImage(urlString: String) async -> Image? {
        if let cached = cachedImage(for: urlString) {
            return cached
        }

        guard let request = buildRequest(for: urlString) else {
            return nil
        }

        do {
            let data = try await APIClient.sendRaw(request)
            cacheImageData(data, for: urlString)
            return makeImage(from: data)
        } catch {
            return nil
        }
    }

    static func downloadToTempFile(urlString: String, fileExtension: String) async -> URL? {
        guard let request = buildRequest(for: urlString) else { return nil }

        do {
            let data = try await APIClient.sendRaw(request)

            let tempDir = FileManager.default.temporaryDirectory
            let fileName = "beeper-\(UUID().uuidString).\(fileExtension)"
            let fileURL = tempDir.appending(path: fileName)
            try data.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }

    static func clearTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        ) else { return }

        for fileURL in contents where fileURL.lastPathComponent.hasPrefix("beeper-") {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    static func makeImage(from data: Data) -> Image? {
        #if os(macOS)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #else
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #endif
    }

    // MARK: - Image cache helpers

    private final class ImageWrapper {
        #if os(macOS)
        let platformImage: NSImage?
        #else
        let platformImage: UIImage?
        #endif

        #if os(macOS)
        init(image: NSImage) { platformImage = image }
        #else
        init(image: UIImage) { platformImage = image }
        #endif
    }
}
