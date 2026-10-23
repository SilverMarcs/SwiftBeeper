import Foundation

/// Resolves Matrix media to URLs and files the views can use.
enum MatrixMedia {
    /// A URL the image library can load. Matrix sources use a reserved host
    /// that MatrixURLProtocol serves from the local file cache.
    static func displayURL(for source: String?) -> URL? {
        guard let source, let sourceURL = URL(string: source) else { return nil }
        guard isMatrixSource(sourceURL) else { return sourceURL }

        var components = URLComponents(url: MatrixFiles.assetURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "url", value: source)]
        return components?.url
    }

    /// A temporary copy of the cached media with the given extension, for
    /// players and previews that pick a decoder from the file name. Repeat
    /// requests for the same media reuse the copy.
    static func temporaryFile(for source: String, fileExtension: String) async -> URL? {
        guard let sourceURL = URL(string: source), isMatrixSource(sourceURL) else { return nil }
        let output = URL.temporaryDirectory.appending(path: "beeper-\(sourceURL.lastPathComponent).\(fileExtension)")
        if FileManager.default.fileExists(atPath: output.path) { return output }
        do {
            let cached = try await MatrixRuntime.shared.localAsset(source)
            try FileManager.default.copyItem(at: cached, to: output)
            return output
        } catch {
            // A concurrent request for the same media may have copied it first.
            return FileManager.default.fileExists(atPath: output.path) ? output : nil
        }
    }

    /// The core's cached file for the media. Read or copy it; don't modify it.
    static func localFile(for source: String) async -> URL? {
        try? await MatrixRuntime.shared.localAsset(source)
    }

    static func clearTemporaryFiles() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: URL.temporaryDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for fileURL in contents where fileURL.lastPathComponent.hasPrefix("beeper-") {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func isMatrixSource(_ url: URL) -> Bool {
        url.scheme == "mxc" || url.scheme == "localmxc"
    }
}
