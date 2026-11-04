import Foundation

/// Bridges deliver a multi-photo send (a WhatsApp album, several iMessage
/// photos) as one Matrix event per image. These rules decide which of those
/// events the timeline folds into a single gallery row.
extension Message {
    /// Longest pause between two photos that still reads as one send.
    static let galleryGap: TimeInterval = 2 * 60

    /// A single still image with nothing else to render: no caption, no
    /// reply, not deleted. GIFs keep their own animated bubble.
    var isGalleryImage: Bool {
        guard isDeleted != true, !hasText, linkedMessageID?.isEmpty != false,
              let attachments, attachments.count == 1, let attachment = attachments.first else { return false }
        return attachment.type == .image && attachment.isGif != true && attachment.resolvedURL != nil
    }

    /// Whether this message joins the gallery that `previous` belongs to.
    func continuesGallery(after previous: Message) -> Bool {
        isGalleryImage && previous.isGalleryImage
            && senderID == previous.senderID
            && timestamp.timeIntervalSince(previous.timestamp) <= Self.galleryGap
            && !TimelineEntry.showsTimestamp(before: timestamp, previous: previous.timestamp)
    }
}
