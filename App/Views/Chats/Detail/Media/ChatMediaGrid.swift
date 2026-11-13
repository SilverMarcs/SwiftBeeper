import SwiftMediaViewer
import SwiftUI

/// Photos and videos as a grid of squares. Photos page together in one
/// fullscreen gallery; a video downloads, then plays in Quick Look.
struct ChatMediaGrid: View {
    let messages: [Message]
    let columns: [GridItem]
    /// Runs as the last tile appears, to load the next page.
    var onReachEnd: (() -> Void)? = nil

    @State private var preparingVideoID: Message.ID?
    @State private var videoURL: URL?

    var body: some View {
        let gallery = ChatMediaGallery(messages: messages)
        SMVGallery(images: gallery.imageURLs, targetSize: MediaBubbleSize.decodePixelSize) {
            LazyVGrid(columns: columns, spacing: ImageGalleryLayout.spacing) {
                ForEach(messages) { message in
                    if let attachment = message.attachments?.first {
                        ChatMediaTile(
                            attachment: attachment,
                            galleryIndex: gallery.imageIndices[message.id],
                            isPreparingVideo: preparingVideoID == message.id
                        ) {
                            Task { await play(attachment, of: message) }
                        }
                        .onAppear {
                            if message.id == messages.last?.id { onReachEnd?() }
                        }
                    }
                }
            }
        }
        .quickLookPreview($videoURL)
    }

    private func play(_ attachment: Attachment, of message: Message) async {
        preparingVideoID = message.id
        defer { preparingVideoID = nil }
        videoURL = await attachment.previewFile()
    }
}
