import SwiftUI

/// One square photo in a sending gallery, matching `ImageGalleryTile`.
struct OutgoingImageGalleryTile: View {
    let image: Image
    /// Photos beyond the grid, counted over this tile when nonzero.
    let hiddenCount: Int

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                image
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .overlay {
                if hiddenCount > 0 {
                    Rectangle()
                        .fill(.black.opacity(0.45))
                        .overlay {
                            Text("+\(hiddenCount)")
                                .font(.title2)
                                .bold()
                                .foregroundStyle(.white)
                        }
                }
            }
    }
}
