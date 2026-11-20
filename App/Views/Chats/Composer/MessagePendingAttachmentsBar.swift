import SwiftMediaViewer
import SwiftUI

/// The composer's queued attachments, shown only while there are some,
/// above the field. Tapping a photo opens the same fullscreen viewer as a
/// sent photo gallery, paging through the queued photos.
struct MessagePendingAttachmentsBar: View {
    let composer: Composer

    var body: some View {
        if !composer.pendingAttachments.isEmpty {
            let attachments = composer.pendingAttachments
            let imageURLs = attachments.compactMap(PendingAttachmentImageSource.url(for:))
            SMVGallery(images: imageURLs, targetSize: MediaBubbleSize.decodePixelSize, showsPageIndicator: false) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { pending in
                            let imageURL = PendingAttachmentImageSource.url(for: pending)
                            PendingAttachmentPreview(
                                pending: pending,
                                imageURL: imageURL,
                                galleryIndex: imageURL.flatMap(imageURLs.firstIndex(of:))
                            ) {
                                composer.pendingAttachments.removeAll { $0.id == pending.id }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}
