import Foundation

/// The card shown in a message's bubble for one of its links, from the
/// message's bridge or the homeserver's preview of the page.
struct MessageLinkPreview: Codable, Equatable, Sendable {
    /// What the card opens: the link as it appears in the message.
    let url: String
    /// The link's host without a leading "www.".
    let domain: String
    let title: String?
    let description: String?
    /// Matrix media, shown through the local media cache like attachments.
    let imageURL: String?
    let imageWidth: Int?
    let imageHeight: Int?

    /// The image's width over its height, when the preview gave its size.
    var imageAspectRatio: CGFloat? {
        guard let imageWidth, let imageHeight, imageWidth > 0, imageHeight > 0 else { return nil }
        return CGFloat(imageWidth) / CGFloat(imageHeight)
    }
}
