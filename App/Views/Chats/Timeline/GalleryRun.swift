import Foundation

/// Consecutive messages the timeline may fold into one gallery row: an
/// optional leading text or album notice, the photos, and an optional
/// trailing text. At most one of them carries text, which the row shows as
/// the gallery's caption. Fewer than two photos stay as separate rows.
struct GalleryRun {
    private(set) var messages: [Message]
    private var photoCount: Int
    private var hasCaption: Bool
    /// Set once a trailing text joins; nothing follows it.
    private var isClosed = false

    init(startingWith message: Message) {
        messages = [message]
        photoCount = message.isGalleryPhoto ? 1 : 0
        hasCaption = message.hasText && !message.isAlbumAnnouncement
    }

    /// The rows this run renders as: one gallery, or each message alone.
    var rows: [[Message]] {
        photoCount >= 2 ? [messages] : messages.map { [$0] }
    }

    /// Adds `next` when it continues this run, reporting whether it did.
    mutating func append(_ next: Message) -> Bool {
        guard accepts(next) else { return false }
        messages.append(next)
        if next.isGalleryPhoto {
            photoCount += 1
        } else {
            isClosed = true
        }
        hasCaption = hasCaption || next.hasText
        return true
    }

    private func accepts(_ next: Message) -> Bool {
        guard !isClosed, let head = messages.first, let last = messages.last,
              head.isGalleryPhoto || head.isGalleryText || head.isAlbumAnnouncement,
              // The row's reply quote, thread footer, and thread label come
              // from its first message, so later ones can't carry their own.
              !next.hasReply, next.thread == nil, next.isThreadBroadcast == head.isThreadBroadcast,
              next.threadRootID == head.threadRootID
        else { return false }

        if next.isGalleryPhoto {
            guard !(next.hasText && hasCaption) else { return false }
            // A leading text must be split off the same remote message; the
            // album notice's photos follow it as they download.
            let gap = photoCount == 0 && !head.isAlbumAnnouncement ? Message.galleryPartGap : Message.galleryGap
            return last.isFollowed(byGalleryPart: next, within: gap)
        }
        return next.isGalleryText && !next.isAlbumAnnouncement
            && photoCount >= 2 && !hasCaption
            && last.isFollowed(byGalleryPart: next, within: Message.galleryPartGap)
    }
}
