import SwiftUI

extension View {
    /// Lays media out at its bubble size, scaling down proportionally when
    /// the column is narrower (a small window, or beside the thread
    /// inspector) instead of overflowing it. The size is known before the
    /// media loads, so the row's height doesn't jump.
    func mediaBubbleFrame(_ size: CGSize) -> some View {
        Color.clear
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .frame(maxWidth: size.width)
            .overlay { self }
    }
}
