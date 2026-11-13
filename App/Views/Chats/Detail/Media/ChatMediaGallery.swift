import Foundation

/// The photos of a media grid, in order, for its fullscreen gallery. Videos
/// play on their own and aren't part of it.
struct ChatMediaGallery {
    private(set) var imageURLs: [URL] = []
    /// Each photo's message, mapped to its place in `imageURLs`.
    private(set) var imageIndices: [Message.ID: Int] = [:]

    init(messages: [Message]) {
        for message in messages {
            guard let attachment = message.attachments?.first, attachment.type == .image,
                  let url = MatrixMedia.displayURL(for: attachment.resolvedURL) else { continue }
            imageIndices[message.id] = imageURLs.count
            imageURLs.append(url)
        }
    }
}
