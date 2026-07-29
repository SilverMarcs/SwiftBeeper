import Foundation
import CryptoKit

enum AuthenticatedImageLoader {
    /// Builds a plain URL that SwiftMediaViewer's `CachedAsyncImage`/`SMVImage`
    /// can load without custom headers: mxc/localmxc/file URLs are routed
    /// through the assets proxy with an asset-specific signature. The API
    /// bearer token itself never appears in the image or video URL.
    static func displayURL(for urlString: String?) -> URL? {
        guard let urlString, let sourceURL = URL(string: urlString) else { return nil }

        guard sourceURL.scheme == "mxc" || sourceURL.scheme == "localmxc" || sourceURL.scheme == "file" else {
            return sourceURL
        }

        guard var components = URLComponents(url: APIConfiguration.assetsProxyURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        guard let signature = assetAccessSignature(for: urlString) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "url", value: urlString),
            URLQueryItem(name: "assetAccessSignature", value: signature),
        ]
        return components.url
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

    private static func assetAccessSignature(for assetURL: String) -> String? {
        let accessToken = APIClient.accessToken
        guard !accessToken.isEmpty else { return nil }

        let key = SymmetricKey(data: Data(accessToken.utf8))
        let authenticationCode = HMAC<SHA256>.authenticationCode(
            for: Data(assetURL.utf8),
            using: key
        )
        return authenticationCode.map { byte in
            let value = String(byte, radix: 16)
            return value.count == 1 ? "0\(value)" : value
        }.joined()
    }
}
