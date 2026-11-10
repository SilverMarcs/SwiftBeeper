import Foundation

/// Bridges deliver a multi-photo send as one Matrix event per photo, and each
/// network places its text differently: WhatsApp and Telegram caption one of
/// the photos, Discord and Slack send the text as its own part just before
/// them, Messenger and Instagram just after, and WhatsApp heads an album with
/// a "Sent an album" notice. These rules fold any of those shapes into one
/// gallery row: the photos in a grid with the text below.
extension Message {
    /// Longest pause between two photos that still reads as one send.
    static let galleryGap: TimeInterval = 2 * 60

    /// Longest gap between a photo and a text the network split off the same
    /// message. Parts of one remote message share its timestamp, or land
    /// within a moment of each other.
    static let galleryPartGap: TimeInterval = 1

    /// A single still image, which can be a gallery photo. It may carry a
    /// caption and, as the gallery's first photo, a reply. GIFs keep their
    /// own animated bubble.
    var isGalleryPhoto: Bool {
        guard isDeleted != true, let attachments, attachments.count == 1,
              let attachment = attachments.first else { return false }
        return attachment.type == .image && attachment.isGif != true && attachment.resolvedURL != nil
    }

    /// Text alone that the sender wrote, which a gallery can show as its
    /// caption. Bridge notices, like a pending decryption, stay apart.
    var isGalleryText: Bool {
        isDeleted != true && isNotice != true && attachments?.isEmpty != false && hasText
    }

    /// The notice WhatsApp's bridge sends ahead of an album's photos. The
    /// grid already says as much, so a gallery hides it.
    var isAlbumAnnouncement: Bool {
        guard isNotice == true, isDeleted != true, attachments?.isEmpty != false,
              let text = visibleText else { return false }
        return text.wholeMatch(of: /Sent an album( with [^\n]+)?:/) != nil
    }

    var hasReply: Bool { linkedMessageID?.isEmpty == false }

    /// Whether `next` follows this message closely enough, from the same
    /// sender and section, to share its row.
    func isFollowed(byGalleryPart next: Message, within gap: TimeInterval) -> Bool {
        next.senderID == senderID
            && next.timestamp.timeIntervalSince(timestamp) <= gap
            && !TimelineEntry.showsTimestamp(before: next.timestamp, previous: timestamp)
    }
}
