import SwiftUI

/// A sending message's photos as the same grid its confirmed gallery shows,
/// so the row keeps its shape when the server echo replaces it.
struct OutgoingImageGalleryView: View {
    let images: [Image]
    let state: OutgoingMessageState

    var body: some View {
        let layout = ImageGalleryLayout(imageCount: images.count)
        Grid(horizontalSpacing: ImageGalleryLayout.spacing, verticalSpacing: ImageGalleryLayout.spacing) {
            ForEach(layout.rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { index in
                        OutgoingImageGalleryTile(image: images[index], hiddenCount: layout.hiddenCount(onTile: index))
                    }
                }
            }
        }
        .frame(maxWidth: MediaBubbleSize.maxWidth)
        .overlay {
            switch state {
            case .sending:
                ZStack {
                    Color.black.opacity(0.18)
                    ProgressView()
                        .tint(.white)
                }
            case .failed:
                Color.black.opacity(0.12)
            }
        }
        .clipShape(.rect(cornerRadius: 12))
    }
}
