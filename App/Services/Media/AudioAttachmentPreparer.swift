import AVFoundation
import OSLog
import SwiftOGG

private let logger = Logger(subsystem: "Relay", category: "AudioAttachment")

/// Turns a Matrix audio attachment into a local file AVFoundation can play,
/// transcoding Ogg Opus voice messages (which it can't) to M4A.
enum AudioAttachmentPreparer {
    static func playableFile(for source: String, mimeType: String?) async -> URL? {
        let fileExtension = fileExtension(for: mimeType)
        guard let fileURL = await MatrixMedia.temporaryFile(for: source, fileExtension: fileExtension) else {
            logger.error("Failed to download audio: \(source)")
            return nil
        }
        guard isOggOpus(mimeType: mimeType, fileExtension: fileExtension) else { return fileURL }

        let m4aURL = fileURL.deletingPathExtension().appendingPathExtension("m4a")
        // A previous play may have converted this file already.
        if FileManager.default.fileExists(atPath: m4aURL.path) { return m4aURL }
        do {
            // CPU-bound transcode; hop off the main actor (the project default)
            // to keep the UI responsive.
            try await Task.detached(priority: .userInitiated) {
                try OGGConverter.convertOpusOGGToM4aFile(src: fileURL, dest: m4aURL)
            }.value
            return m4aURL
        } catch {
            // Don't leave a partial file for the next play to reuse.
            try? FileManager.default.removeItem(at: m4aURL)
            logger.error("OGG to M4A conversion failed: \(error)")
            return nil
        }
    }

    /// The file's real duration, when AVFoundation can read it.
    static func duration(of fileURL: URL) async -> Double? {
        guard let duration = try? await AVURLAsset(url: fileURL).load(.duration),
              duration.isNumeric else { return nil }
        return duration.seconds
    }

    /// A clean file extension from a MIME type like "audio/ogg; codecs=opus".
    private static func fileExtension(for mimeType: String?) -> String {
        guard let mimeType else { return "m4a" }
        let base = mimeType.split(separator: ";").first.map(String.init) ?? mimeType
        let subtype = base.split(separator: "/").last?.trimmingCharacters(in: .whitespaces) ?? "m4a"
        switch subtype {
        case "mpeg": return "mp3"
        case "mp4", "x-m4a", "m4a": return "m4a"
        case "ogg", "opus": return "ogg"
        case "x-wav", "wav": return "wav"
        case "aac": return "aac"
        case "x-caf", "x-aiff": return "caf"
        default: return subtype
        }
    }

    private static func isOggOpus(mimeType: String?, fileExtension: String) -> Bool {
        let mimeType = mimeType?.lowercased() ?? ""
        return fileExtension == "ogg" || mimeType.contains("ogg") || mimeType.contains("opus")
    }
}
