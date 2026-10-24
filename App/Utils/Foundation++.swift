import Foundation
import UniformTypeIdentifiers

extension Calendar {
    /// Shared calendar for display formatting. `Calendar.current` allocates a new
    /// value on every access; this cached, auto-updating instance avoids that in
    /// the hot path (message rows, timestamp dividers, sidebar rows).
    static let app = Calendar.autoupdatingCurrent
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isBlank: Bool {
        trimmed.isEmpty
    }
}

extension URL {
    var mimeType: String {
        UTType(filenameExtension: pathExtension)?.preferredMIMEType ?? "application/octet-stream"
    }
}
