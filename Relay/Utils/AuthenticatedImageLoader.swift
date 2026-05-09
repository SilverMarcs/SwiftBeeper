import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum AuthenticatedImageLoader {
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
        guard let request = buildRequest(for: urlString) else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }
            return makeImage(from: data)
        } catch {
            return nil
        }
    }

    static func downloadToTempFile(urlString: String, fileExtension: String) async -> URL? {
        guard let request = buildRequest(for: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return nil
            }

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
}
