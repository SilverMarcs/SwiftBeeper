import SwiftUI

extension OutgoingMessage {
    /// The previews to show as one grid while sending: two or more still
    /// photos and nothing else, as the timeline folds them once confirmed.
    /// Nil for any other send, which shows its attachments one by one.
    var galleryImages: [Image]? {
        guard attachments.count >= 2,
              attachments.allSatisfy({ $0.mimeType != "image/gif" }) else { return nil }
        let images = attachments.compactMap { $0.decodedImage()?.image }
        return images.count == attachments.count ? images : nil
    }
}
