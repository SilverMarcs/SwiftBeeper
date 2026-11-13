import SwiftUI

/// Stands in for a thumbnail that is loading or has no image.
struct ChatMediaThumbnailPlaceholder: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .subtleBackground()
    }
}
