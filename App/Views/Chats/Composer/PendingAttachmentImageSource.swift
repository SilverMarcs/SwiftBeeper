import Foundation
import Synchronization
import SwiftMediaViewer

/// Serves picked images to SwiftMediaViewer by URL while they're in a
/// composer, so its fullscreen viewer opens them as it does sent photos.
/// `Composer` adds and removes them as its attachments change.
enum PendingAttachmentImageSource {
    nonisolated static let scheme = "relay-pending"

    nonisolated private static let images = Mutex<[UUID: Data]>([:])

    /// The image's URL for SwiftMediaViewer; nil for non-images.
    static func url(for attachment: PendingAttachment) -> URL? {
        guard attachment.mimeType.hasPrefix("image/") else { return nil }
        return URL(string: "\(scheme)://\(attachment.id.uuidString)")
    }

    /// Serves the images added since `old` and drops the ones removed.
    static func update(from old: [PendingAttachment], to new: [PendingAttachment]) {
        let kept = Set(new.map(\.id))
        images.withLock { images in
            for attachment in old where !kept.contains(attachment.id) {
                images[attachment.id] = nil
            }
            for attachment in new where url(for: attachment) != nil {
                images[attachment.id] = attachment.fileData
            }
        }
    }

    nonisolated static func register() {
        SMVImageSources.register(scheme: scheme) { url, _ in
            guard let id = url.host.flatMap(UUID.init(uuidString:)),
                  let data = images.withLock({ $0[id] }) else {
                throw CocoaError(.fileNoSuchFile)
            }
            return data
        }
    }
}
